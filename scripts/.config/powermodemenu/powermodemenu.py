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

# Glass theme variables (card radius). Colors follow theme tokens when available.
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
# Localization (system language: LC_MESSAGES/LANG)
# -----------------------------------------------------------------------------
def detect_lang():
    lang = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "").lower()
    if lang.startswith("es"):
        return "es"
    if lang.startswith("pt"):
        return "pt"
    return "en"

STRINGS = {
    "en": {
        "battery": "Battery",
        "power_source": "Power Source",
        "ac": "Power Adapter",
        "bat": "Battery",
        "energy_mode": "Energy Mode",
        "automatic": "Automatic",
        "low": "Low Power",
        "high": "High Power",
        "gaming": "Gaming",
        "gaming_hint": "Gaming: Connect the power adapter",
        "no_apps": "No Apps Using Significant Energy",
        "apps_using": "Apps Using Significant Energy",
        "battery_settings": "Battery Settings",
        "charge_limit": "Charge limit",
        "applied": "Applied",
        "error": "Error",
        "dry_run": "dry-run",
        "notif_unplug_title": "Power mode",
        "notif_unplug_body": "Charger unplugged: switched to Automatic",
        "notif_gaming_title": "Gaming mode",
        "notif_gaming_body": "Connect the power adapter",
    },
    "es": {
        "battery": "Batería",
        "power_source": "Fuente de energía",
        "ac": "Adaptador de corriente",
        "bat": "Batería",
        "energy_mode": "Modo de energía",
        "automatic": "Automático",
        "low": "Bajo consumo",
        "high": "Alto rendimiento",
        "gaming": "Juego",
        "gaming_hint": "Juego: conecta el adaptador de corriente",
        "no_apps": "Ninguna app usa mucha energía",
        "apps_using": "Apps con alto consumo de energía",
        "battery_settings": "Ajustes de batería",
        "charge_limit": "Límite de carga",
        "applied": "Aplicado",
        "error": "Error",
        "dry_run": "prueba",
        "notif_unplug_title": "Modo de energía",
        "notif_unplug_body": "Cargador desconectado: cambiado a Automático",
        "notif_gaming_title": "Modo Juego",
        "notif_gaming_body": "Conecta el adaptador de corriente",
    },
    "pt": {
        "battery": "Bateria",
        "power_source": "Fonte de energia",
        "ac": "Adaptador de energia",
        "bat": "Bateria",
        "energy_mode": "Modo de energia",
        "automatic": "Automático",
        "low": "Baixo consumo",
        "high": "Alto desempenho",
        "gaming": "Jogo",
        "gaming_hint": "Jogo: conecte o adaptador de energia",
        "no_apps": "Nenhum app usando energia significativa",
        "apps_using": "Apps usando energia significativa",
        "battery_settings": "Ajustes de bateria",
        "charge_limit": "Limite de carga",
        "applied": "Aplicado",
        "error": "Erro",
        "dry_run": "teste",
        "notif_unplug_title": "Modo de energia",
        "notif_unplug_body": "Carregador desconectado: alterado para Automático",
        "notif_gaming_title": "Modo Jogo",
        "notif_gaming_body": "Conecte o adaptador de energia",
    },
}
L = STRINGS[detect_lang()]

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
    return L["ac"] if is_on_ac() else L["bat"]


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
def _is_light_mode():
    mode = read_text(Path.home() / ".config/theme/mode")
    return (mode or "").strip().lower() == "light"

def load_theme_css():
    display = Gdk.Display.get_default()
    if not display:
        return
    # Base theme tokens (colors) used across Glasshouse panels
    for path, prio in [
        (Path.home() / ".config/theme/current.css", Gtk.STYLE_PROVIDER_PRIORITY_USER),
        (Path.home() / "dotfiles/waybar/.config/waybar/settings.css", Gtk.STYLE_PROVIDER_PRIORITY_USER + 1),
    ]:
        if not path.is_file():
            continue
        provider = Gtk.CssProvider()
        try:
            provider.load_from_path(str(path))
            Gtk.StyleContext.add_provider_for_display(display, provider, prio)
        except Exception:
            pass

def css():
    light = _is_light_mode()
    if light:
        bg = "alpha(@bg, 0.82)"
        fg = "@text"
        sub = "@subtext"
        border = "alpha(@border, 0.9)"
        row_hover = "alpha(@text, 0.06)"
        row_sel = "alpha(@accent, 0.18)"
        sep = "alpha(@border, 0.7)"
        badge_bg = "alpha(@text, 0.10)"
        card_shadow = "0 12px 30px rgba(0,0,0,0.18)"
    else:
        bg = "alpha(@bg, 0.78)"
        fg = "@text"
        sub = "@subtext"
        border = "alpha(@border, 0.9)"
        row_hover = "alpha(@text, 0.08)"
        row_sel = "alpha(@accent, 0.22)"
        sep = "alpha(@border, 0.7)"
        badge_bg = "alpha(@text, 0.14)"
        card_shadow = "0 14px 34px rgba(0,0,0,0.35)"
    return f"""
    /* Compact floating card (anchored TOP+RIGHT, sized to content) */
    window {{ background: transparent; }}
    .pm-card {{
        background: {bg};
        color: {fg};
        border: 1px solid {border};
        border-radius: {RADIUS}px;
        padding: 12px;
        box-shadow: {card_shadow};
    }}
    .pm-header {{ font-weight: 700; font-size: 15px; color: {fg}; }}
    .pm-sub {{ color: {sub}; font-size: 12px; }}
    .pm-sep {{ background: {sep}; min-height: 1px; margin: 8px 0; }}
    .pm-section {{ color: {sub}; font-size: 12px; font-weight: 600; margin: 6px 2px 4px 2px; letter-spacing: 0.5px; }}

    /* Mode rows: reset GTK button chrome; only inner row background changes */
    button.pm-mode,
    button.pm-mode:hover,
    button.pm-mode:active,
    button.pm-mode:checked,
    button.pm-mode:focus,
    button.pm-mode:focus-visible {{
        background: none;
        background-image: none;
        background-color: transparent;
        box-shadow: none;
        text-shadow: none;
        -gtk-icon-shadow: none;
        border: none;
        outline: none;
        padding: 0;
        margin: 0;
        min-height: 0;
        min-width: 0;
        border-radius: 12px;
    }}
    .pm-row {{
        border-radius: 12px;
        padding: 8px 10px;
        min-height: 30px;
        transition: background-color 120ms ease, border-color 120ms ease;
    }}
    .pm-row.setting-row {{
        background-color: @surface;
        border: 1px solid @border;
    }}
    button.pm-mode:hover .pm-row,
    button.pm-mode:focus .pm-row,
    button.pm-mode:focus-visible .pm-row {{
        background-color: alpha(@text, 0.12);
        border-color: alpha(@border, 0.9);
    }}
    button.pm-mode:hover .pm-row.selected,
    button.pm-mode:focus .pm-row.selected {{
        background-color: {row_sel};
        border-color: alpha(@accent, 0.45);
    }}
    .pm-row.selected {{
        background-color: {row_sel};
        border-color: alpha(@accent, 0.45);
    }}
    .pm-badge {{
        min-width: 32px; min-height: 32px; border-radius: 16px;
        background: alpha(@text, 0.14); color: {fg}; font-size: 13px; font-weight: 700;
    }}
    .pm-badge.selected {{ background: @accent; color: #ffffff; }}
    .pm-disabled {{ opacity: 0.45; }}
    .pm-hint {{ color: {sub}; font-size: 11px; }}

    /* Battery Settings toggle row */
    button.pm-toggle,
    button.pm-toggle:hover,
    button.pm-toggle:active,
    button.pm-toggle:focus,
    button.pm-toggle:focus-visible {{
        background: none;
        background-image: none;
        background-color: transparent;
        box-shadow: none;
        text-shadow: none;
        border: none;
        outline: none;
        padding: 0;
        margin: 0;
        min-height: 0;
        border-radius: 12px;
    }}
    .pm-toggle-row {{
        border-radius: 12px;
        padding: 10px 12px;
        transition: background-color 120ms ease, border-color 120ms ease;
    }}
    .pm-toggle-row.setting-row {{
        background-color: @surface;
        border: 1px solid @border;
    }}
    button.pm-toggle:hover .pm-toggle-row,
    button.pm-toggle:focus .pm-toggle-row {{
        background-color: alpha(@text, 0.12);
    }}
    .pm-chevron {{ color: {sub}; font-size: 14px; font-weight: 600; }}

    .pm-charge {{
        margin-top: 6px;
    }}
    .pm-charge.setting-row {{
        padding: 10px 12px;
    }}
    /* Presets: flat action buttons */
    button.pm-preset {{
        min-height: 0;
        padding: 4px 12px;
        background-color: transparent;
        background-image: none;
        border: 1px solid @border;
        border-radius: 10px;
        color: @text;
        box-shadow: none;
        text-shadow: none;
    }}
    button.pm-preset:hover {{
        background-color: alpha(@text, 0.10);
        border-color: alpha(@accent, 0.5);
    }}
    button.pm-preset:active {{
        background-color: alpha(@text, 0.16);
    }}
    scale trough {{ border-radius: 999px; min-height: 6px; background: alpha(@text, 0.12); }}
    scale highlight {{ border-radius: 999px; min-height: 6px; background: @accent; }}
    scale slider {{ min-width: 18px; min-height: 18px; border-radius: 9px; background: @text; box-shadow: none; }}
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
        # Compact popup: ~300px wide, height sized to content
        self.set_default_size(300, -1)

        # Card
        self.card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.card.add_css_class("pm-card")
        self.card.set_hexpand(False)
        self.card.set_vexpand(False)
        self.set_child(self.card)

        self.build_ui()
        self.refresh_all()
        # Refresh live info while open (status/app), every 5s
        self.refresh_source = GLib.timeout_add_seconds(5, self.refresh_live)
        self.connect("close-request", self.on_close)

        # Close on Escape
        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.on_key)
        self.add_controller(key)
        # Close when focus leaves the popup (click outside / switch window)
        focus = Gtk.EventControllerFocus()
        focus.connect("leave", lambda *_: self.close())
        self.add_controller(focus)

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
        t = Gtk.Label(label=L["battery"], xalign=0)
        t.add_css_class("pm-header")
        t.set_hexpand(True)
        hdr.append(t)
        self.pct_label = Gtk.Label(label="--%", xalign=1)
        self.pct_label.add_css_class("pm-header")
        hdr.append(self.pct_label)
        self.card.append(hdr)

        self.source_label = Gtk.Label(label=f"{L['power_source']}: —", xalign=0)
        self.source_label.add_css_class("pm-sub")
        self.card.append(self.source_label)

        self.sep()
        sec = Gtk.Label(label=L["energy_mode"], xalign=0)
        sec.add_css_class("pm-section")
        self.card.append(sec)

        # Mode rows
        self.modes_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.card.append(self.modes_box)
        for mode, label, icon in (
            ("automatic", L["automatic"], "A"),
            ("low", L["low"], "L"),
            ("high", L["high"], "H"),
            ("gaming", L["gaming"], "G"),
        ):
            row = self.make_mode_row(mode, label, icon)
            self.modes_box.append(row)

        self.gaming_hint = Gtk.Label(label="", xalign=0)
        self.gaming_hint.add_css_class("pm-hint")
        self.card.append(self.gaming_hint)

        self.sep()
        self.energy_label = Gtk.Label(label=L["no_apps"], xalign=0)
        self.energy_label.add_css_class("pm-sub")
        self.energy_label.set_wrap(True)
        self.card.append(self.energy_label)

        self.sep()
        # Battery Settings toggle (collapsed by default, smooth reveal)
        self.charge_revealer = Gtk.Revealer()
        self.charge_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.charge_revealer.set_transition_duration(180)
        self.charge_revealer.set_reveal_child(False)  # collapsed by default

        toggle_btn = Gtk.Button()
        toggle_btn.add_css_class("pm-toggle")
        toggle_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        toggle_row.add_css_class("pm-toggle-row")
        toggle_row.add_css_class("setting-row")
        tlabel = Gtk.Label(label=L["battery_settings"], xalign=0)
        tlabel.set_hexpand(True)
        toggle_row.append(tlabel)
        self.charge_chevron = Gtk.Label(label="›")
        self.charge_chevron.add_css_class("pm-chevron")
        toggle_row.append(self.charge_chevron)
        toggle_btn.set_child(toggle_row)
        toggle_btn.connect("clicked", self.on_toggle_charge)
        self.card.append(toggle_btn)

        self.charge_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.charge_panel.add_css_class("pm-charge")
        self.charge_panel.add_css_class("setting-row")
        self.build_charge_panel()
        self.charge_revealer.set_child(self.charge_panel)
        self.card.append(self.charge_revealer)

    def build_charge_panel(self):
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.charge_title = Gtk.Label(label=L["charge_limit"], xalign=0)
        self.charge_title.add_css_class("pm-sub")
        self.charge_title.set_hexpand(True)
        top.append(self.charge_title)
        self.charge_value = Gtk.Label(label="--%", xalign=1)
        self.charge_value.add_css_class("pm-sub")
        top.append(self.charge_value)
        self.charge_panel.append(top)
        # Slider 20-100 (always visible)
        adj = Gtk.Adjustment(value=get_charge_limit() or 100, lower=20, upper=100, step_increment=1, page_increment=5)
        self.charge_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        self.charge_scale.set_digits(0)
        self.charge_scale.set_draw_value(False)
        self.charge_scale.set_hexpand(True)
        self.charge_scale.connect("value-changed", self.on_charge_slider)
        self.charge_panel.append(self.charge_scale)
        # Presets 60/80/100
        presets = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        presets.set_halign(Gtk.Align.CENTER)
        for val in (60, 80, 100):
            b = Gtk.Button(label=f"{val}%")
            b.add_css_class("pm-preset")
            b.connect("clicked", lambda _b, v=val: self.set_charge_limit(v))
            presets.append(b)
        self.charge_panel.append(presets)
        self.charge_msg = Gtk.Label(label="", xalign=0)
        self.charge_msg.add_css_class("pm-hint")
        self.charge_panel.append(self.charge_msg)
        self._charge_apply_source = None

    def on_toggle_charge(self, *_args):
        revealed = not self.charge_revealer.get_reveal_child()
        self.charge_revealer.set_reveal_child(revealed)
        self.charge_chevron.set_text("⌄" if revealed else "›")
        if revealed:
            # Read real value when opened
            self.refresh_charge_limit_ui()

    def make_mode_row(self, mode, label, icon):
        btn = Gtk.Button()
        btn.add_css_class("pm-mode")
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add_css_class("pm-row")
        row.add_css_class("setting-row")
        badge = Gtk.Label(label=icon)
        badge.add_css_class("pm-badge")
        badge.set_size_request(32, 32)
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
            notify(L["notif_gaming_title"], L["notif_gaming_body"])
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
            notify(L["notif_gaming_title"], L["notif_gaming_body"])
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
        value = int(value)
        self.charge_scale.set_value(value)
        self.charge_value.set_text(f"{value}%")
        rc, out, err = run_helper(["charge-limit", str(value)], dry_run=self.dry_run)
        if rc == 0:
            self.charge_msg.set_text(f"{L['applied']}: {value}%" + (f" ({L['dry_run']})" if self.dry_run else ""))
        else:
            detail = (err or out or "error").strip().splitlines()[0]
            self.charge_msg.set_text(f"{L['error']}: {detail}")
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
            self.charge_value.set_text(f"{int(val)}%")
        return False

    def refresh_all(self):
        cap = get_capacity()
        self.pct_label.set_text(f"{cap}%" if cap is not None else "--%")
        self.source_label.set_text(f"{L['power_source']}: {get_power_source_label()}")
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
            notify(L["notif_unplug_title"], L["notif_unplug_body"])
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
            self.gaming_hint.set_text(L["gaming_hint"])
        else:
            self.gaming_hint.set_text("")

    def refresh_energy(self):
        name = top_energy_process()
        if name:
            self.energy_label.set_text(f"{L['apps_using']}: {name}")
        else:
            self.energy_label.set_text(L["no_apps"])


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
    # Load theme/base CSS then popup-specific CSS
    load_theme_css()
    provider = Gtk.CssProvider()
    provider.load_from_data(css().encode("utf-8"))
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    app = App(dry_run=args.dry_run)
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
