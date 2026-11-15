#!/usr/bin/env python3
"""
powermodemenu: macOS-style Battery popup for Waybar/Hyprland (Wayland).

- GTK4 + gtk4-layer-shell popup (overlay), namespace: powermodemenu
- Shows battery/power-source state, selectable power modes, top energy app,
  and "Battery Settings…" with charge-limit control (moved here as single source).
- The UI does NOT run as root. Privileged actions are delegated to the helper:
    /usr/local/lib/powermodemenu/powermodemenu-helper
  via pkexec (preferred) or sudo (NOPASSWD drop-in). See docs in repo.

Build stages supported:
  (1) UI with live read-only data and --dry-run for mode/limit actions
  (2) Real mode switching through helper (when --dry-run not set)
  (3) Auto-apply on plug/unplug via udev/systemd pieces (installed separately)
  (4) Battery Settings charge limit control inside this popup

Run:
  powermodemenu.py [--dry-run] [--status]
  --dry-run  : do not change system state; helper is called with --dry-run
  --status   : print current mode, power source and charge limit, then exit
"""
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Gtk4LayerShell as LayerShell

# -----------------------------------------------------------------------------
# Configuration (edit to match your setup)
# -----------------------------------------------------------------------------
NAMESPACE = "powermodemenu"
# Anchor margins (popup below top-right Waybar battery area)
MARGIN_TOP = 42   # pixels below top edge (adjust to sit under Waybar)
MARGIN_RIGHT = 12 # align with Waybar right margin

# Glass theme variables (dark defaults; set LIGHT_GLASS=True for light variant)
LIGHT_GLASS = False
RADIUS = 18

# Optional WiFi power-save tweak (OFF by default; unstable on some chipsets e.g. MT7902)
WIFI_POWERSAVE_TWEAK = False

# Top CPU process threshold (%) to show as "Using Significant Energy"
SIGNIFICANT_CPU_PERCENT = 20.0

# Paths
STATE_DIR = Path.home() / ".local/state/powermodemenu"
STATE_MODE_FILE = STATE_DIR / "mode"
HELPER_INSTALLED = Path("/usr/local/lib/powermodemenu/powermodemenu-helper")
# Fallback to repo helper for development/testing
HELPER_REPO = Path(__file__).resolve().parents[2] / "scripts/.local/lib/powermodemenu/powermodemenu-helper"

MODES = ("automatic", "low", "high", "gaming")

# -----------------------------------------------------------------------------
# Helpers: system reads (no privileges required)
# -----------------------------------------------------------------------------
def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="ignore").strip()
    except Exception:
        return None


def get_battery_path():
    for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        if (bat / "capacity").is_file():
            return bat
    return None


def get_capacity():
    bat = get_battery_path()
    if not bat:
        return None
    v = read_text(bat / "capacity")
    return int(v) if v and v.isdigit() else None


def get_status_raw():
    bat = get_battery_path()
    return read_text(bat / "status") if bat else None


def is_on_ac():
    for base in sorted(Path("/sys/class/power_supply").glob("*")):
        if (base / "online").is_file():
            name = base.name.upper()
            if name.startswith(("AC", "ADP", "MAINS")):
                return read_text(base / "online") == "1"
    # fallback: charging/full often implies AC on many laptops
    st = (get_status_raw() or "").lower()
    if st in ("charging", "full"):
        return True
    return False


def get_power_source_label():
    return "Power Adapter" if is_on_ac() else "Battery"


def get_charge_limit():
    for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        v = read_text(bat / "charge_control_end_threshold")
        if v and v.isdigit():
            return int(v)
    if shutil.which("asusctl"):
        try:
            r = subprocess.run(["asusctl", "battery", "info"], capture_output=True, text=True, timeout=8)
            if r.returncode == 0:
                m = re.search(r"(\d+)\s*%", r.stdout)
                if m:
                    return int(m.group(1))
        except Exception:
            pass
    return None


def load_mode():
    try:
        m = STATE_MODE_FILE.read_text(encoding="utf-8").strip()
        return m if m in MODES else "automatic"
    except Exception:
        return "automatic"


def save_mode(mode):
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        STATE_MODE_FILE.write_text(mode + "\n", encoding="utf-8")
    except Exception as e:
        print(f"powermodemenu: cannot save mode: {e}", file=sys.stderr)


def helper_path():
    if HELPER_INSTALLED.is_file():
        return str(HELPER_INSTALLED)
    if HELPER_REPO.is_file():
        return str(HELPER_REPO)
    return None


def run_helper(args, dry_run=False):
    """Invoke privileged helper via pkexec/sudo. Returns (rc, out, err)."""
    hp = helper_path()
    if not hp:
        msg = "helper not found"
        print(f"powermodemenu: {msg}", file=sys.stderr)
        return 1, "", msg
    cmd = [hp] + args
    if dry_run:
        cmd.append("--dry-run")
    # Try pkexec first (polkit), then sudo -n, then direct (if already root / dev)
    for prefix in (["pkexec"], ["sudo", "-n"], []):
        if prefix and not shutil.which(prefix[0]):
            continue
        try:
            r = subprocess.run(prefix + cmd, capture_output=True, text=True, timeout=30)
            # pkexec/sudo may fail auth; if so try next
            if prefix and r.returncode in (126, 127):
                continue
            return r.returncode, r.stdout or "", r.stderr or ""
        except Exception as e:
            last = str(e)
    return 1, "", "failed to invoke helper"


def top_energy_process():
    """Return name of top CPU process above threshold, or None."""
    try:
        out = subprocess.check_output(
            ["ps", "-eo", "pcpu=,comm=", "--sort=-pcpu"], text=True, timeout=5
        )
    except Exception:
        return None
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        try:
            cpu = float(parts[0].replace(",", "."))
        except Exception:
            continue
        name = parts[1].strip()
        if cpu >= SIGNIFICANT_CPU_PERCENT and name not in ("ps", "powermodemenu", "python3", "python"):
            return name
    return None


def notify(summary, body=""):
    if shutil.which("notify-send"):
        try:
            subprocess.Popen(["notify-send", "-a", "Power Mode", summary, body], start_new_session=True)
        except Exception:
            pass


# -----------------------------------------------------------------------------
# GTK4 UI
# -----------------------------------------------------------------------------
def css():
    if LIGHT_GLASS:
        bg = "rgba(245,245,247,0.82)"
        fg = "#1d1d1f"
        sub = "rgba(0,0,0,0.55)"
        border = "rgba(0,0,0,0.12)"
        row_hover = "rgba(0,0,0,0.06)"
        row_sel = "rgba(10,132,255,0.14)"
        sep = "rgba(0,0,0,0.10)"
    else:
        bg = "rgba(40,40,44,0.78)"
        fg = "#f5f5f7"
        sub = "rgba(255,255,255,0.60)"
        border = "rgba(255,255,255,0.14)"
        row_hover = "rgba(255,255,255,0.08)"
        row_sel = "rgba(10,132,255,0.22)"
        sep = "rgba(255,255,255,0.10)"
    return f"""
    window {{ background: transparent; }}
    .pm-card {{
        background: {bg};
        color: {fg};
        border: 1px solid {border};
        border-radius: {RADIUS}px;
        padding: 12px;
        box-shadow: 0 10px 30px rgba(0,0,0,0.25);
    }}
    .pm-header {{ font-weight: 700; font-size: 15px; }}
    .pm-sub {{ color: {sub}; font-size: 12px; }}
    .pm-sep {{ background: {sep}; min-height: 1px; margin: 6px 0; }}
    .pm-section {{ color: {sub}; font-size: 12px; font-weight: 600; margin: 4px 2px; }}
    .pm-row {{
        border-radius: 10px; padding: 6px 8px; margin: 1px 0;
        transition: background 120ms ease;
    }}
    .pm-row:hover, .pm-row:focus {{ background: {row_hover}; outline: none; }}
    .pm-row.selected {{ background: {row_sel}; }}
    .pm-badge {{
        min-width: 22px; min-height: 22px; border-radius: 11px;
        background: rgba(255,255,255,0.18); color: {fg}; font-size: 12px;
    }}
    .pm-badge.selected {{ background: #0a84ff; color: #ffffff; }}
    .pm-disabled {{ opacity: 0.45; }}
    .pm-hint {{ color: {sub}; font-size: 11px; }}
    button.flat {{ background: transparent; border: none; }}
    """


class PowerModeMenu(Gtk.ApplicationWindow):
    def __init__(self, app, dry_run=False):
        super().__init__(application=app)
        self.dry_run = dry_run
        self.selected_mode = load_mode()
        self.rows = {}
        self.refresh_source = None
        self._last_on_ac = is_on_ac()

        # Layer shell setup: overlay popup anchored top-right
        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, NAMESPACE)
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.ON_DEMAND)
        LayerShell.set_anchor(self, LayerShell.Edge.TOP, True)
        LayerShell.set_anchor(self, LayerShell.Edge.RIGHT, True)
        LayerShell.set_anchor(self, LayerShell.Edge.BOTTOM, False)
        LayerShell.set_anchor(self, LayerShell.Edge.LEFT, False)
        LayerShell.set_margin(self, LayerShell.Edge.TOP, MARGIN_TOP)
        LayerShell.set_margin(self, LayerShell.Edge.RIGHT, MARGIN_RIGHT)

        self.set_decorated(False)
        self.set_default_size(340, 10)

        # Card
        self.card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.card.add_css_class("pm-card")
        self.set_child(self.card)

        self.build_ui()
        self.refresh_all()
        # Refresh live info while open (status/app), every 5s
        self.refresh_source = GLib.timeout_add_seconds(5, self.refresh_live)
        self.connect("close-request", self.on_close)

        # Close on Escape / focus loss handled via key controller
        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.on_key)
        self.add_controller(key)

    def on_close(self, *_):
        if self.refresh_source:
            GLib.source_remove(self.refresh_source)
            self.refresh_source = None
        return False

    def sep(self):
        s = Gtk.Box()
        s.add_css_class("pm-sep")
        s.set_size_request(-1, 1)
        self.card.append(s)

    def build_ui(self):
        # Header: "Battery" + percentage
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        t = Gtk.Label(label="Battery", xalign=0)
        t.add_css_class("pm-header")
        t.set_hexpand(True)
        hdr.append(t)
        self.pct_label = Gtk.Label(label="--%", xalign=1)
        self.pct_label.add_css_class("pm-header")
        hdr.append(self.pct_label)
        self.card.append(hdr)

        self.source_label = Gtk.Label(label="Power Source: —", xalign=0)
        self.source_label.add_css_class("pm-sub")
        self.card.append(self.source_label)

        self.sep()
        sec = Gtk.Label(label="Energy Mode", xalign=0)
        sec.add_css_class("pm-section")
        self.card.append(sec)

        # Mode rows
        self.modes_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.card.append(self.modes_box)
        for mode, label, icon in (
            ("automatic", "Automatic", "A"),
            ("low", "Low Power", "L"),
            ("high", "High Power", "H"),
            ("gaming", "Gaming", "G"),
        ):
            row = self.make_mode_row(mode, label, icon)
            self.modes_box.append(row)

        self.gaming_hint = Gtk.Label(label="", xalign=0)
        self.gaming_hint.add_css_class("pm-hint")
        self.card.append(self.gaming_hint)

        self.sep()
        self.energy_label = Gtk.Label(label="No Apps Using Significant Energy", xalign=0)
        self.energy_label.add_css_class("pm-sub")
        self.energy_label.set_wrap(True)
        self.card.append(self.energy_label)

        self.sep()
        # Battery Settings… row
        bs = Gtk.Button()
        bs.add_css_class("flat")
        bs_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        l = Gtk.Label(label="Battery Settings…", xalign=0)
        l.set_hexpand(True)
        bs_row.append(l)
        bs_row.append(Gtk.Label(label="›"))
        bs.set_child(bs_row)
        bs.connect("clicked", lambda *_: self.toggle_charge_panel())
        self.card.append(bs)

        # Inline charge limit panel (hidden by default)
        self.charge_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.charge_panel.set_visible(False)
        self.charge_panel.set_margin_top(4)
        self.card.append(self.charge_panel)
        self.build_charge_panel()

    def build_charge_panel(self):
        lab = Gtk.Label(label="Charge limit", xalign=0)
        lab.add_css_class("pm-sub")
        self.charge_panel.append(lab)
        # Presets 60/80/100
        presets = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for val in (60, 80, 100):
            b = Gtk.Button(label=f"{val}%")
            b.connect("clicked", lambda _b, v=val: self.set_charge_limit(v))
            presets.append(b)
        self.charge_panel.append(presets)
        # Slider 20-100
        adj = Gtk.Adjustment(value=100, lower=20, upper=100, step_increment=1, page_increment=5)
        self.charge_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        self.charge_scale.set_digits(0)
        self.charge_scale.set_draw_value(True)
        self.charge_scale.connect("value-changed", self.on_charge_slider)
        self.charge_panel.append(self.charge_scale)
        self.charge_msg = Gtk.Label(label="", xalign=0)
        self.charge_msg.add_css_class("pm-hint")
        self.charge_panel.append(self.charge_msg)
        self._charge_apply_source = None

    def toggle_charge_panel(self):
        self.charge_panel.set_visible(not self.charge_panel.get_visible())

    def make_mode_row(self, mode, label, icon):
        btn = Gtk.Button()
        btn.add_css_class("flat")
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add_css_class("pm-row")
        badge = Gtk.Label(label=icon)
        badge.add_css_class("pm-badge")
        badge.set_size_request(22, 22)
        row.append(badge)
        txt = Gtk.Label(label=label, xalign=0)
        txt.set_hexpand(True)
        row.append(txt)
        btn.set_child(row)
        btn.connect("clicked", lambda *_: self.select_mode(mode))
        self.rows[mode] = (btn, row, badge)
        return btn

    def on_key(self, _ctrl, keyval, _keycode, state):
        name = Gdk.keyval_name(keyval)
        if name == "Escape":
            self.close()
            return True
        # Simple Up/Down/Enter navigation across mode rows
        order = [m for m in MODES if m in self.rows]
        focus = self.get_focus()
        idx = 0
        for i, m in enumerate(order):
            b, _, _ = self.rows[m]
            if focus is b or (focus and focus.is_ancestor(b)):
                idx = i
                break
        if name == "Down":
            self.rows[order[(idx + 1) % len(order)]][0].grab_focus()
            return True
        if name == "Up":
            self.rows[order[(idx - 1) % len(order)]][0].grab_focus()
            return True
        if name in ("Return", "KP_Enter"):
            for m in order:
                b, _, _ = self.rows[m]
                if focus is b or (focus and focus.is_ancestor(b)):
                    self.select_mode(m)
                    return True
        return False

    def select_mode(self, mode):
        on_ac = is_on_ac()
        if mode == "gaming" and not on_ac:
            notify("Gaming mode", "Connect the power adapter")
            return
        prev = self.selected_mode
        save_mode(mode)
        self.selected_mode = mode
        self.update_mode_rows()
        # Apply via helper (dry-run respected)
        rc, out, err = run_helper(["apply", mode], dry_run=self.dry_run)
        if rc == 2 and "REFUSED" in (out + err):
            # helper refused (e.g. gaming on battery)
            save_mode(prev)
            self.selected_mode = prev
            self.update_mode_rows()
            notify("Gaming mode", "Connect the power adapter")
            return
        # Manage hypridle inhibition for gaming (user session, no root)
        if mode == "gaming":
            self.enter_gaming_session()
        else:
            self.leave_gaming_session()
        # Apply hypridle timeout profile for the selected mode/AC state
        self.apply_idle_profile()
        # Close after choosing a mode (as specified)
        self.close()

    def enter_gaming_session(self):
        # Stop hypridle / inhibit idle like gaming-toggle does (user-level)
        try:
            subprocess.run(["pkill", "-x", "hypridle"], check=False)
            if shutil.which("systemd-inhibit"):
                subprocess.Popen([
                    "systemd-inhibit", "--what=idle:sleep:handle-lid-switch",
                    "--mode=block", "--why=Gaming mode (powermodemenu)", "sleep", "infinity"
                ], start_new_session=True)
        except Exception:
            pass

    def leave_gaming_session(self):
        # Best-effort: stop our gaming inhibitor (idle profile apply will restart hypridle)
        try:
            subprocess.run(["pkill", "-f", "Gaming mode (powermodemenu)"], check=False)
        except Exception:
            pass

    def apply_idle_profile(self):
        script = Path.home() / ".config/powermodemenu/apply-idle-profile"
        if not script.is_file():
            # fallback to repo copy
            script = Path(__file__).resolve().parent / "apply-idle-profile"
        if script.is_file():
            try:
                subprocess.Popen([str(script)], start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

    def set_charge_limit(self, value):
        rc, out, err = run_helper(["charge-limit", str(int(value))], dry_run=self.dry_run)
        if rc == 0:
            self.charge_msg.set_text(f"Applied: {int(value)}%" + (" (dry-run)" if self.dry_run else ""))
        else:
            detail = (err or out or "error").strip().splitlines()[0]
            self.charge_msg.set_text(f"Error: {detail}")
        GLib.timeout_add(600, self.refresh_charge_limit_ui)

    def on_charge_slider(self, scale):
        if self._charge_apply_source:
            GLib.source_remove(self._charge_apply_source)
        self._charge_apply_source = GLib.timeout_add(350, lambda: (self._clear_charge_src(), self.set_charge_limit(int(scale.get_value()))))

    def _clear_charge_src(self):
        self._charge_apply_source = None
        return False

    def refresh_charge_limit_ui(self):
        val = get_charge_limit()
        if val is not None:
            self.charge_scale.set_value(val)
        return False

    def refresh_all(self):
        cap = get_capacity()
        self.pct_label.set_text(f"{cap}%" if cap is not None else "--%")
        self.source_label.set_text(f"Power Source: {get_power_source_label()}")
        self.update_mode_rows()
        self.refresh_energy()
        self.refresh_charge_limit_ui()

    def refresh_live(self):
        if not self.get_visible():
            return False
        self.refresh_all()
        on_ac = is_on_ac()
        # Auto-fallback: if gaming active but unplugged, fall back to automatic
        if self.selected_mode == "gaming" and not on_ac:
            notify("Power mode", "Charger unplugged: switched to Automatic")
            self.select_mode("automatic")
            return False
        # Automatic mode: reapply when AC state changes (EPP/ASPM/maxfreq + idle profile)
        if self.selected_mode == "automatic" and on_ac != self._last_on_ac:
            self._last_on_ac = on_ac
            run_helper(["apply", "automatic"], dry_run=self.dry_run)
            self.apply_idle_profile()
        else:
            self._last_on_ac = on_ac
        return True

    def update_mode_rows(self):
        on_ac = is_on_ac()
        for mode, (btn, row, badge) in self.rows.items():
            selected = (mode == self.selected_mode)
            row.remove_css_class("selected") if not selected else row.add_css_class("selected")
            badge.remove_css_class("selected") if not selected else badge.add_css_class("selected")
            disabled = (mode == "gaming" and not on_ac)
            btn.set_sensitive(not disabled)
            row.remove_css_class("pm-disabled") if not disabled else row.add_css_class("pm-disabled")
        if not on_ac:
            self.gaming_hint.set_text("Gaming: Connect the power adapter")
        else:
            self.gaming_hint.set_text("")

    def refresh_energy(self):
        name = top_energy_process()
        if name:
            self.energy_label.set_text(f"Apps Using Significant Energy: {name}")
        else:
            self.energy_label.set_text("No Apps Using Significant Energy")


class App(Gtk.Application):
    def __init__(self, dry_run=False):
        super().__init__(application_id="glasshouse.powermodemenu")
        self.dry_run = dry_run
        self.win = None

    def do_activate(self):
        # Toggle: if open, close
        if self.win and self.win.get_visible():
            self.win.close()
            self.win = None
            return
        self.win = PowerModeMenu(self, dry_run=self.dry_run)
        self.win.present()


def print_status():
    info = {
        "mode": load_mode(),
        "power_source": "ac" if is_on_ac() else "battery",
        "charge_limit": get_charge_limit(),
    }
    print(json.dumps(info, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print actions, do not change system")
    ap.add_argument("--status", action="store_true", help="print current mode, power source and charge limit")
    args = ap.parse_args()
    if args.status:
        print_status()
        return 0
    # Load CSS
    provider = Gtk.CssProvider()
    provider.load_from_data(css().encode("utf-8"))
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    app = App(dry_run=args.dry_run)
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
