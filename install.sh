#!/usr/bin/env bash
#
# Glasshouse dotfiles installer (v1)
#
# What it does:
#   Links the Glasshouse configuration from this repository into $HOME and
#   creates the runtime defaults the desktop needs. Privileged actions (session
#   launcher, SDDM theme, system-wide fonts, package installation) only run when
#   the corresponding flag is passed.
#
# Dependencies:
#   bash, coreutils, findutils, jq, python3 (JSONC validation), and the desktop
#   commands listed in check_dependencies(). Optional: shellcheck, luac, rofi,
#   fc-match, Hyprland (for hyprctl configerrors). Optional Arch package
#   profiles can be installed with --install-desktop-deps / --install-sddm-deps.
#
# Usage:
#   ./install.sh [--dry-run] [--yes] [--verbose] [--allow-nonstandard]
#                [--with-session] [--with-fonts] [--with-sddm]
#                [--install-deps] [--install-desktop-deps] [--install-sddm-deps]
#   ./install.sh --help
#
# The installer is idempotent: re-running it does not duplicate links and does
# not overwrite existing runtime files.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$SCRIPT_DIR"
HOME_REAL="$(realpath -m -- "$HOME" 2>/dev/null || printf '%s' "$HOME")"
REPO_REAL="$(realpath -m -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"
EXPECTED_REPO="$HOME/dotfiles"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.dotfiles-backup/install-$TIMESTAMP"
MANIFEST="$BACKUP_ROOT/manifest.txt"
TMP_FILES=()

DRY_RUN=0
ASSUME_YES=0
VERBOSE=0
ALLOW_NONSTANDARD=0
WITH_SESSION=0
WITH_FONTS=0
WITH_SDDM=0
INSTALL_DEPS=0
INSTALL_DESKTOP_DEPS=0
INSTALL_SDDM_DEPS=0

FAILURES=0
WARNINGS=0

cleanup() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [[ -n "$f" ]] && rm -f -- "$f"
  done
}
trap cleanup EXIT

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_BLUE=$'\033[34m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
else
  C_RESET=""
  C_BOLD=""
  C_BLUE=""
  C_YELLOW=""
  C_RED=""
  C_GREEN=""
fi

log()   { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
error() { printf '%serr %s %s\n' "$C_RED" "$C_RESET" "$*" >&2; FAILURES=$((FAILURES + 1)); }
vlog()  { if (( VERBOSE )); then printf '     %s\n' "$*"; fi; }

die() {
  error "$*"
  exit 1
}

run() {
  if (( DRY_RUN )); then
    printf '     [dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  vlog "run: $*"
  "$@"
}

banner() {
  printf '\n'
  printf '%s' "$C_BOLD"
  cat <<'EOF'

  ░██████  ░██                                  ░██     ░██
 ░██   ░██ ░██                                  ░██     ░██
░██        ░██  ░██████    ░███████   ░███████  ░██     ░██  ░███████  ░██    ░██  ░███████   ░███████
░██  █████ ░██       ░██  ░██        ░██        ░██████████ ░██    ░██ ░██    ░██ ░██        ░██    ░██
░██     ██ ░██  ░███████   ░███████   ░███████  ░██     ░██ ░██    ░██ ░██    ░██  ░███████  ░█████████
 ░██  ░███ ░██ ░██   ░██         ░██        ░██ ░██     ░██ ░██    ░██ ░██   ░███        ░██ ░██
  ░█████░█ ░██  ░█████░██  ░███████   ░███████  ░██     ░██  ░███████   ░█████░██  ░███████   ░███████

EOF
  printf '%s' "$C_RESET"
  printf '  Glasshouse dotfiles installer (v1)\n'
  printf '  repo: %s\n' "$REPO"
  printf '  home: %s\n\n' "$HOME"
}

usage() {
  cat <<'EOF'
Glasshouse dotfiles installer (v1)

This installer links the Glasshouse configuration into $HOME and creates the
runtime defaults used by the session. It is safe to run more than once.

Flags:
  --dry-run              Show every action without changing anything.
  --yes                  Do not ask for confirmation (still required for safe
                         use in scripts).
  --verbose              Print extra detail, including no-op links.
  --allow-nonstandard    Allow running when the repo is not at $HOME/dotfiles.
                         The session scripts hardcode $HOME/dotfiles, so this is
                         only useful for testing.
  --with-session         Install the privileged session files with sudo:
                           /usr/local/bin/hyprland-glass
                           /usr/share/wayland-sessions/hyprland-glass.desktop
  --with-fonts           Install SF Pro system-wide with fonts-install, but only
                         if ~/.local/share/fonts/San-Francisco-Pro-Fonts-master
                         exists. Then run fonts-apply.
  --with-sddm            Install/update the Glasshouse SDDM theme with
                         sddm-install. This edits /etc/sddm.conf and SDDM theme
                         files. SDDM is never restarted.
  --install-deps         Install missing required Arch packages with pacman.
  --install-desktop-deps Install the optional Arch desktop dependency profile
                         with pacman (opt-in; no AUR/paru, no pacman -Sy).
  --install-sddm-deps    Install the optional Arch SDDM dependency profile with
                         pacman (opt-in; no AUR/paru, no pacman -Sy).
  -h, --help             Show this help.

User-level links (default, no sudo):
  theme/.config/theme                       -> ~/.config/theme
  nwg-dock-hyprland/.config/nwg-dock-hyprland -> ~/.config/nwg-dock-hyprland
  kitty/.config/kitty/kitty.conf            -> ~/.config/kitty/kitty.conf
  fastfetch/.config/fastfetch/config.jsonc  -> ~/.config/fastfetch/config.jsonc
  scripts/.local/bin/*                      -> ~/.local/bin/<name>
  theme/.local/bin/theme-toggle             -> ~/.local/bin/theme-toggle
  wallpapers/Pictures                       -> ~/Pictures (if absent)
  wallpapers/Pictures/wallpapers            -> ~/Pictures/wallpapers (if it exists)

Runtime defaults (only created if missing):
  ~/.config/theme/mode                      = dark
  ~/.config/theme/appearance.conf           = safe appearance defaults
  ~/.config/theme/avatar.conf               = initials avatar
  ~/.config/theme/current.{conf,css,lua,rasi,kitty}
                                            -> theme/<mode>/colors.*
  ~/.cache/nwg-dock-pinned                  = empty file
  ~/.cache/waybar/config.json               = generated by waybar-build

Backups:
  Anything replaced is copied to:
    ~/.dotfiles-backup/install-<timestamp>/
  and recorded in manifest.txt. A correct symlink is left untouched. This
  includes different symlinks, regular files, and real directories. If
  ~/.config/theme is a real directory, its runtime files are first copied into
  the repo theme target (only when missing) and the whole directory is backed
  up before it is replaced by a symlink.

Privileged steps and risks:
  No privileged action runs unless its flag is passed. --with-sddm edits
  /etc/sddm.conf and the installed SDDM theme; a wrong greeter configuration
  can leave the login screen broken. Keep a TTY available before rebooting.
  SDDM is never restarted by this installer. The Glasshouse SDDM theme uses
  QtQuick 2.15 / QtQuick.Controls 2.15 / QtGraphicalEffects 1.0; Qt5/Qt6
  greeter packaging can be ambiguous across setups, so use --install-sddm-deps
  only when it matches your SDDM/greeter stack.

Package installation:
  --install-deps installs missing required Arch packages. --install-desktop-deps
  and --install-sddm-deps are separate opt-in profiles (Arch/pacman only). The
  installer checks package availability with pacman -Si when possible, warns if
  a package may not be in configured repos (AUR/manual), and only runs sudo
  pacman -S --needed after confirmation or --yes. --dry-run never installs.

Examples:
  ./install.sh --dry-run --verbose
  ./install.sh --dry-run --verbose --yes --install-deps --install-desktop-deps --install-sddm-deps
  ./install.sh --yes
  ./install.sh --yes --install-deps
  ./install.sh --yes --install-desktop-deps
  ./install.sh --yes --with-session
  ./install.sh --yes --install-sddm-deps --with-sddm
  ./install.sh --yes --with-fonts --with-sddm
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --verbose|-v) VERBOSE=1 ;;
      --allow-nonstandard) ALLOW_NONSTANDARD=1 ;;
      --with-session) WITH_SESSION=1 ;;
      --with-fonts) WITH_FONTS=1 ;;
      --with-sddm) WITH_SDDM=1 ;;
      --install-deps) INSTALL_DEPS=1 ;;
      --install-desktop-deps) INSTALL_DESKTOP_DEPS=1 ;;
      --install-sddm-deps) INSTALL_SDDM_DEPS=1 ;;
      -h|--help) usage; exit 0 ;;
      --)
        shift
        if (($# > 0)); then
          die "Unexpected argument: $1"
        fi
        break
        ;;
      -*)
        die "Unknown flag: $1 (use --help)"
        ;;
      *)
        die "Unexpected argument: $1 (use --help)"
        ;;
    esac
    shift
  done
}

confirm() {
  local prompt="$1"
  if (( ASSUME_YES || DRY_RUN )); then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "$prompt (no TTY; re-run with --yes to allow it)"
    return 1
  fi
  local answer
  read -r -p "$prompt [y/N] " answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# General guard for any path this installer creates or writes. The lexical
# check keeps the path under $HOME, and the real parent check prevents a
# symlinked parent from escaping $HOME (or the repo) during mkdir / rm / cp /
# writes. Repo-backed parents (for example ~/.config/theme -> $REPO) remain
# allowed even when the repo itself lives outside $HOME.
assert_safe_write_path() {
  local path="$1"
  local parent parent_real

  if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" || "$path" != "$HOME"/* ]]; then
    error "Refusing to touch unsafe path: $path"
    return 1
  fi

  parent="$(dirname -- "$path")"
  if ! parent_real="$(realpath -m -- "$parent" 2>/dev/null)"; then
    error "Refusing to touch path with unresolvable parent: $path"
    return 1
  fi

  if [[ "$parent_real" == "$HOME_REAL" || "$parent_real" == "$HOME_REAL"/* ||
        "$parent_real" == "$REPO_REAL" || "$parent_real" == "$REPO_REAL"/* ]]; then
    return 0
  fi

  error "Refusing to touch path whose parent escapes \$HOME or the repo: $path -> $parent_real"
  return 1
}

# Link paths use the same guard so symlinked parents cannot escape $HOME or the
# repo during backup, removal, or creation.
assert_safe_link_path() {
  assert_safe_write_path "$1"
}

assert_removable() {
  assert_safe_link_path "$1"
}

label_for() {
  local path="$1"
  local rel="${path#"$HOME"/}"
  rel="${rel//\//__}"
  printf '%s' "${rel:-root}"
}

ensure_backup_root() {
  if [[ -L "$BACKUP_ROOT" ]]; then
    error "Refusing to use symlinked backup root: $BACKUP_ROOT"
    return 1
  fi
  assert_safe_write_path "$MANIFEST" || return 1
  if [[ -d "$BACKUP_ROOT" ]]; then
    return 0
  fi
  mkdir -p -- "$BACKUP_ROOT"
  {
    printf 'Glasshouse install backup\n'
    printf 'timestamp=%s\n' "$TIMESTAMP"
    printf 'repo=%s\n' "$REPO"
    printf 'home=%s\n' "$HOME"
    printf '\ntarget\tbackup\n'
  } > "$MANIFEST"
}

backup_path() {
  local target="$1"
  local label="${2:-}"
  [[ -n "$label" ]] || label="$(label_for "$target")"

  local dest="$BACKUP_ROOT/$label"
  local n=1
  while [[ -e "$dest" || -L "$dest" ]]; do
    dest="$BACKUP_ROOT/${label}.$n"
    n=$((n + 1))
  done

  if (( DRY_RUN )); then
    log "[dry-run] backup $target -> $dest"
    return 0
  fi

  assert_safe_write_path "$dest" || return 1
  ensure_backup_root || return 1
  cp -a -- "$target" "$dest"
  printf '%s\t%s\n' "$target" "$dest" >> "$MANIFEST"
  log "Backup: $target -> $dest"
}

# Link target -> link safely. A correct link is a no-op. Anything else is
# backed up before it is replaced.
safe_link() {
  local target="$1"
  local link="$2"

  assert_safe_link_path "$link" || return 1

  if [[ -L "$link" ]]; then
    local current resolved_current resolved_target
    current="$(readlink -- "$link" 2>/dev/null || true)"
    resolved_current="$(readlink -f -- "$link" 2>/dev/null || true)"
    resolved_target="$(readlink -f -- "$target" 2>/dev/null || true)"
    if [[ -n "$resolved_target" && "$resolved_current" == "$resolved_target" ]] ||
       [[ "$current" == "$target" ]]; then
      vlog "link ok: $link"
      return 0
    fi
    assert_removable "$link" || return 1
    log "Replacing symlink: $link (was -> ${current:-<unreadable>})"
    backup_path "$link" "$(label_for "$link")"
    run rm -f -- "$link"
  elif [[ -e "$link" ]]; then
    assert_removable "$link" || return 1
    if [[ -d "$link" ]]; then
      log "Replacing directory: $link"
      backup_path "$link" "$(label_for "$link")"
      run rm -rf -- "$link"
    else
      log "Replacing file: $link"
      backup_path "$link" "$(label_for "$link")"
      run rm -f -- "$link"
    fi
  else
    vlog "creating link: $link -> $target"
  fi

  run mkdir -p -- "$(dirname -- "$link")"
  run ln -s -- "$target" "$link"
}

copy_missing_tree() {
  local src="$1"
  local dst="$2"
  local item rel
  while IFS= read -r -d '' item; do
    rel="${item#"$src"/}"
    if [[ -e "$dst/$rel" || -L "$dst/$rel" ]]; then
      continue
    fi
    if (( DRY_RUN )); then
      log "[dry-run] preserve missing $item -> $dst/$rel"
      continue
    fi
    mkdir -p -- "$(dirname -- "$dst/$rel")"
    cp -a -- "$item" "$dst/$rel"
    vlog "preserved: $item -> $dst/$rel"
  done < <(find "$src" -mindepth 1 -print0)
}

copy_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    vlog "keep existing runtime: $dst"
    return 0
  fi
  if (( DRY_RUN )); then
    log "[dry-run] preserve runtime $src -> $dst"
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dst")"
  cp -a -- "$src" "$dst"
  log "Preserved runtime: $dst"
}

preserve_theme_runtime() {
  local src="$HOME/.config/theme"
  local dst="$REPO/theme/.config/theme"

  if [[ ! -d "$src" || -L "$src" ]]; then
    return 0
  fi

  log "Preserving runtime files from real $src"
  local item
  for item in appearance.conf avatar.conf avatar.png mode current.conf current.css current.lua current.rasi current.kitty backgrounds avatars/custom; do
    if [[ ! -e "$src/$item" && ! -L "$src/$item" ]]; then
      continue
    fi
    if [[ -d "$src/$item" && ! -L "$src/$item" ]]; then
      if [[ ! -d "$dst/$item" ]]; then
        copy_if_missing "$src/$item" "$dst/$item"
      else
        copy_missing_tree "$src/$item" "$dst/$item"
      fi
    else
      copy_if_missing "$src/$item" "$dst/$item"
    fi
  done
}

link_configs() {
  log "Linking user configuration"
  safe_link "$REPO/theme/.config/theme" "$HOME/.config/theme"
  safe_link "$REPO/nwg-dock-hyprland/.config/nwg-dock-hyprland" "$HOME/.config/nwg-dock-hyprland"
  safe_link "$REPO/kitty/.config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  safe_link "$REPO/fastfetch/.config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"

  local f name
  for f in "$REPO"/scripts/.local/bin/*; do
    [[ -f "$f" ]] || continue
    name="$(basename -- "$f")"
    safe_link "$f" "$HOME/.local/bin/$name"
  done
  safe_link "$REPO/theme/.local/bin/theme-toggle" "$HOME/.local/bin/theme-toggle"
}

ensure_pictures() {
  local pictures="$HOME/Pictures"
  local repo_pics="$REPO/wallpapers/Pictures"

  if [[ ! -e "$pictures" && ! -L "$pictures" ]]; then
    log "Linking Pictures directory"
    safe_link "$repo_pics" "$pictures"
    return 0
  fi

  if [[ -L "$pictures" ]]; then
    local resolved_current resolved_target
    resolved_current="$(readlink -f -- "$pictures" 2>/dev/null || true)"
    resolved_target="$(readlink -f -- "$repo_pics" 2>/dev/null || true)"
    if [[ -n "$resolved_target" && "$resolved_current" == "$resolved_target" ]]; then
      vlog "Pictures link ok: $pictures"
      return 0
    fi
  fi

  if [[ -d "$pictures" ]]; then
    log "Linking wallpapers inside existing Pictures"
    safe_link "$repo_pics/wallpapers" "$pictures/wallpapers"
  else
    warn "$pictures exists but is not a directory; leaving it untouched"
  fi
}

write_if_missing() {
  local file="$1"
  local content="$2"
  if [[ -e "$file" || -L "$file" ]]; then
    vlog "runtime exists: $file"
    return 0
  fi
  if (( DRY_RUN )); then
    log "[dry-run] create $file"
    return 0
  fi
  assert_safe_write_path "$file" || return 1
  mkdir -p -- "$(dirname -- "$file")"
  printf '%s' "$content" > "$file"
  log "Created $file"
}

ensure_current_links() {
  local mode_file="$HOME/.config/theme/mode"
  local mode="dark"
  if [[ -r "$mode_file" ]]; then
    mode="$(<"$mode_file")"
    mode="${mode//[[:space:]]/}"
  fi
  case "$mode" in
    dark|light) ;;
    *)
      warn "Unknown theme mode '$mode'; using dark"
      mode="dark"
      ;;
  esac

  local ext target link
  for ext in conf css lua rasi kitty; do
    target="$REPO/theme/.config/theme/$mode/colors.$ext"
    link="$HOME/.config/theme/current.$ext"
    if [[ ! -e "$target" ]]; then
      warn "Missing color file: $target"
      continue
    fi
    safe_link "$target" "$link"
  done
}

ensure_empty_file() {
  local file="$1"
  if [[ -e "$file" || -L "$file" ]]; then
    vlog "runtime exists: $file"
    return 0
  fi
  if (( DRY_RUN )); then
    log "[dry-run] create empty $file"
    return 0
  fi
  assert_safe_write_path "$file" || return 1
  mkdir -p -- "$(dirname -- "$file")"
  : > "$file"
  log "Created empty $file"
}

run_waybar_build() {
  local cmd="$HOME/.local/bin/waybar-build"
  if (( DRY_RUN )); then
    log "[dry-run] waybar-build"
    return 0
  fi
  if [[ ! -x "$cmd" ]]; then
    warn "waybar-build is not executable; skipping"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is missing; skipping waybar-build"
    return 0
  fi
  assert_safe_write_path "$HOME/.cache/waybar/config.json" || return 1
  if "$cmd"; then
    vlog "waybar-build ok"
  else
    error "waybar-build failed"
  fi
}

create_runtime_defaults() {
  log "Creating runtime defaults (only if missing)"
  local theme_dir="$HOME/.config/theme"
  write_if_missing "$theme_dir/mode" $'dark\n'
  write_if_missing "$theme_dir/appearance.conf" \
    $'lock_bg=desktop\nlock_blur=off\nsddm_bg=desktop\nsddm_blur=on\ndock_enabled=on\ndock_autohide=on\nbar_autohide=off\n'
  write_if_missing "$theme_dir/avatar.conf" $'avatar_mode=initials\navatar_image=\n'
  ensure_current_links
  ensure_empty_file "$HOME/.cache/nwg-dock-pinned"
  run_waybar_build
}

check_repo_location() {
  local expected actual
  expected="$(readlink -f -- "$EXPECTED_REPO" 2>/dev/null || printf '%s' "$EXPECTED_REPO")"
  actual="$(readlink -f -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"

  if [[ "$actual" == "$expected" ]]; then
    vlog "repo location ok: $actual"
    return 0
  fi

  if (( ALLOW_NONSTANDARD )); then
    warn "Repo is not at \$HOME/dotfiles (expected $expected, got $actual)."
    warn "Continuing because --allow-nonstandard was given; session scripts still assume \$HOME/dotfiles."
    return 0
  fi

  error "This v1 installer expects the repo at \$HOME/dotfiles (got $actual)."
  error "Move the repo there, or re-run with --allow-nonstandard for testing."
  exit 1
}

# Command -> Arch package mapping (best-effort; package names may vary by repo).
declare -A CMD_PKG=(
  [hyprctl]=hyprland
  [hyprlock]=hyprlock
  [hypridle]=hypridle
  [waybar]=waybar
  [swaync]=swaync
  [nwg-dock-hyprland]=nwg-dock-hyprland
  [rofi]=rofi
  [kitty]=kitty
  [jq]=jq
  [swaybg]=swaybg
  [grim]=grim
  [slurp]=slurp
  [wl-copy]=wl-clipboard
  [wl-paste]=wl-clipboard
  [cliphist]=cliphist
  [fc-match]=fontconfig
  [python3]=python
  [flock]=util-linux
  [dbus-update-activation-environment]=dbus
  [swaync-client]=swaync
  [start-hyprland]=hyprland
  [notify-send]=libnotify
  [gsettings]=glib2
  [socat]=socat
  [powerprofilesctl]=power-profiles-daemon
  [nm-applet]=network-manager-applet
  [blueman-applet]=blueman
  [blueman-manager]=blueman
  [pamixer]=pamixer
  [brightnessctl]=brightnessctl
  [playerctl]=playerctl
  [magick]=imagemagick
  [zenity]=zenity
  [sddm]=sddm
  [checkupdates]=pacman-contrib
  [systemd-inhibit]=systemd
)

REQUIRED_CMDS=(
  hyprctl hyprlock hypridle waybar swaync nwg-dock-hyprland rofi kitty jq
  swaybg grim slurp wl-copy wl-paste cliphist fc-match python3 flock
)

# Checked as warnings with package hints; not treated as core-required failures.
RELATED_CMDS=(
  dbus-update-activation-environment swaync-client start-hyprland
)

# Desktop/profile-related commands checked as optional warnings.
DESKTOP_CMDS=(
  notify-send gsettings socat powerprofilesctl nm-applet blueman-applet
  blueman-manager pamixer brightnessctl playerctl magick zenity
)

OPTIONAL_CMDS=(
  sddm systemd-inhibit checkupdates paru flatpak
)

# Opt-in Arch package profiles (pacman --needed). No AUR/paru.
DESKTOP_DEPS_PKGS=(
  hyprpolkitagent
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  networkmanager
  network-manager-applet
  blueman
  pamixer
  brightnessctl
  playerctl
  libnotify
  python-gobject
  gtk3
  glib2
  socat
  power-profiles-daemon
  pacman-contrib
  imagemagick
  zenity
)

SDDM_DEPS_PKGS=(
  sddm
  qt5-quickcontrols2
  qt5-graphicaleffects
  fontconfig
)

warn_repo_availability() {
  local profile="$1"
  shift
  local pkg
  if ! command -v pacman >/dev/null 2>&1; then
    warn "pacman not found; cannot check $profile package availability"
    return 0
  fi
  for pkg in "$@"; do
    if ! pacman -Si -- "$pkg" >/dev/null 2>&1; then
      warn "$profile package may not be in configured repos (AUR/manual): $pkg"
    elif (( VERBOSE )); then
      vlog "repo package available: $pkg"
    fi
  done
}

install_pkg_profile() {
  local profile="$1"
  shift
  local pkgs=("$@")

  if ((${#pkgs[@]} == 0)); then
    warn "No packages defined for profile: $profile"
    return 0
  fi

  log "Package profile ($profile): ${pkgs[*]}"
  warn_repo_availability "$profile" "${pkgs[@]}"

  if (( DRY_RUN )); then
    printf '     [dry-run] sudo pacman -S --needed'
    printf ' %q' "${pkgs[@]}"
    printf '\n'
    return 0
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    error "pacman not found; cannot install $profile profile"
    return 0
  fi

  if ! confirm "Install $profile packages with pacman -S --needed?"; then
    warn "Skipped $profile package installation"
    return 0
  fi

  local pacman_args=(pacman -S --needed)
  if (( ASSUME_YES )); then
    pacman_args+=(--noconfirm)
  fi
  pacman_args+=("${pkgs[@]}")
  if run sudo "${pacman_args[@]}"; then
    ok "Package profile installed: $profile"
  else
    error "Package profile installation failed: $profile"
  fi
}

check_command_group() {
  local level="$1" label="$2"
  shift 2
  local cmd pkg msg
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      vlog "$label found: $cmd"
      continue
    fi
    pkg="${CMD_PKG[$cmd]:-}"
    msg="$label missing: $cmd"
    if [[ -n "$pkg" ]]; then
      msg+=" (package: $pkg)"
    fi
    if [[ "$level" == "warn" ]]; then
      warn "$msg"
    else
      vlog "$msg"
    fi
  done
}

check_hyprpolkitagent() {
  local agent="/usr/lib/hyprpolkitagent/hyprpolkitagent"
  if [[ -x "$agent" ]]; then
    vlog "desktop agent found: $agent"
  elif command -v hyprpolkitagent >/dev/null 2>&1; then
    vlog "desktop agent found in PATH: hyprpolkitagent"
  else
    warn "Desktop agent missing: hyprpolkitagent ($agent; package: hyprpolkitagent)"
  fi
}

check_dependencies() {
  log "Checking commands"
  local missing_pkgs=()
  local seen=()
  local cmd pkg

  for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      vlog "found: $cmd"
      continue
    fi
    warn "Missing required command: $cmd"
    pkg="${CMD_PKG[$cmd]:-}"
    if [[ -n "$pkg" ]]; then
      local already=0
      local existing
      for existing in "${seen[@]}"; do
        if [[ "$existing" == "$pkg" ]]; then
          already=1
          break
        fi
      done
      if (( already == 0 )); then
        seen+=("$pkg")
        missing_pkgs+=("$pkg")
      fi
    fi
  done

  # wl-paste is checked with wl-copy (same package) as part of required commands.
  if command -v wl-copy >/dev/null 2>&1 && ! command -v wl-paste >/dev/null 2>&1; then
    warn "Missing related command: wl-paste (expected with wl-copy; package: wl-clipboard)"
  fi

  if ((${#missing_pkgs[@]} > 0)); then
    printf 'Suggested package install:\n  sudo pacman -S --needed'
    printf ' %q' "${missing_pkgs[@]}"
    printf '\n'

    if (( INSTALL_DEPS )); then
      if ! command -v pacman >/dev/null 2>&1; then
        error "pacman not found; cannot use --install-deps"
      elif confirm "Install missing packages with pacman?"; then
        local pacman_args=(pacman -S --needed)
        if (( ASSUME_YES )); then
          pacman_args+=(--noconfirm)
        fi
        pacman_args+=("${missing_pkgs[@]}")
        if run sudo "${pacman_args[@]}"; then
          ok "Package installation finished"
        else
          error "Package installation failed"
        fi
      else
        warn "Skipped package installation"
      fi
    else
      warn "Re-run with --install-deps to install them automatically"
    fi
  else
    ok "All required commands are present"
  fi

  check_command_group warn "Related command" "${RELATED_CMDS[@]}"
  check_command_group warn "Desktop command" "${DESKTOP_CMDS[@]}"
  check_hyprpolkitagent

  for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      vlog "optional found: $cmd"
    else
      case "$cmd" in
        paru) warn "Optional command missing: paru (AUR helper; install from AUR if wanted)" ;;
        checkupdates) warn "Optional command missing: checkupdates (package: pacman-contrib)" ;;
        systemd-inhibit) warn "Optional command missing: systemd-inhibit (package: systemd)" ;;
        magick) warn "Optional command missing: magick (package: imagemagick)" ;;
        *) warn "Optional command missing: $cmd" ;;
      esac
    fi
  done
}

install_session() {
  log "Installing privileged Hyprland session files (sudo)"
  if (( DRY_RUN )); then
    log "[dry-run] sudo install -Dm755 $REPO/scripts/.local/bin/hyprland-glass /usr/local/bin/hyprland-glass"
    log "[dry-run] sudo install -Dm644 <generated desktop file> /usr/share/wayland-sessions/hyprland-glass.desktop"
    return 0
  fi

  if ! confirm "Install /usr/local/bin/hyprland-glass and the Wayland session file with sudo?"; then
    warn "Skipped session installation"
    return 0
  fi

  if ! sudo install -Dm755 "$REPO/scripts/.local/bin/hyprland-glass" /usr/local/bin/hyprland-glass; then
    error "Could not install /usr/local/bin/hyprland-glass"
    return 0
  fi

  local desktop_file
  desktop_file="$(mktemp)"
  TMP_FILES+=("$desktop_file")
  cat > "$desktop_file" <<'EOF'
[Desktop Entry]
Name=Hyprland (Glasshouse)
Comment=Glasshouse Hyprland session
Exec=/usr/local/bin/hyprland-glass
Type=Application
DesktopNames=Hyprland
EOF

  if sudo install -Dm644 "$desktop_file" /usr/share/wayland-sessions/hyprland-glass.desktop; then
    ok "Session installed: log out and pick 'Hyprland (Glasshouse)'"
  else
    error "Could not install /usr/share/wayland-sessions/hyprland-glass.desktop"
  fi
}

install_fonts() {
  local font_src="$HOME/.local/share/fonts/San-Francisco-Pro-Fonts-master"
  log "Installing fonts (sudo)"
  if [[ ! -d "$font_src" ]]; then
    warn "Font source not found: $font_src; skipping --with-fonts"
    return 0
  fi

  if (( DRY_RUN )); then
    log "[dry-run] $HOME/.local/bin/fonts-install"
    log "[dry-run] $HOME/.local/bin/fonts-apply"
    return 0
  fi

  if ! confirm "Install SF Pro system-wide and apply font settings?"; then
    warn "Skipped font installation"
    return 0
  fi

  if "$HOME/.local/bin/fonts-install"; then
    ok "System fonts installed"
  else
    error "fonts-install failed"
  fi

  if "$HOME/.local/bin/fonts-apply"; then
    ok "Font settings applied"
  else
    error "fonts-apply failed"
  fi
}

sddm_qml_modules_dubious() {
  local root
  local controls=0 effects=0
  for root in /usr/lib/qt/qml /usr/lib/qt5/qml /usr/lib/qt6/qml /usr/lib64/qt5/qml; do
    [[ -d "$root/QtQuick/Controls.2" ]] && controls=1
    [[ -d "$root/QtGraphicalEffects" ]] && effects=1
  done
  (( controls == 0 || effects == 0 ))
}

install_sddm() {
  log "Installing SDDM theme (sudo); SDDM will not be restarted"

  if ! command -v sddm >/dev/null 2>&1; then
    warn "sddm command not found. Try --install-sddm-deps (Arch/pacman; Qt5/Qt6 greeter packaging can vary)."
  elif sddm_qml_modules_dubious; then
    warn "SDDM/QML modules for the Glasshouse theme look uncertain in common locations (QtQuick 2.15/Controls 2.15/QtGraphicalEffects 1.0). Try --install-sddm-deps if your greeter needs Qt5 modules."
  fi

  if (( DRY_RUN )); then
    log "[dry-run] $HOME/.local/bin/sddm-install <theme-mode>"
    return 0
  fi

  warn "SDDM risk: sddm-install edits /etc/sddm.conf and /usr/share/sddm/themes/glass."
  if ! confirm "Continue with SDDM theme installation?"; then
    warn "Skipped SDDM installation"
    return 0
  fi

  local mode="dark"
  local mode_file="$HOME/.config/theme/mode"
  if [[ -r "$mode_file" ]]; then
    mode="$(<"$mode_file")"
    mode="${mode//[[:space:]]/}"
  fi
  case "$mode" in
    dark|light) ;;
    *) mode="dark" ;;
  esac

  if "$HOME/.local/bin/sddm-install" "$mode"; then
    ok "SDDM theme installed (mode: $mode). Reboot to see it; SDDM was not restarted."
  else
    error "sddm-install failed"
  fi
}

validate_bash_scripts() {
  log "Validating bash scripts"
  local files=("$REPO/install.sh")
  local f first output
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$REPO/scripts/.local/bin" "$REPO/theme/.local/bin" -maxdepth 1 -type f -print0 2>/dev/null)

  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    IFS= read -r first < "$f" || true
    if [[ "$first" != *bash* && "$first" != *'/sh'* ]]; then
      continue
    fi
    if output="$(bash -n "$f" 2>&1)"; then
      vlog "bash -n ok: ${f#"$REPO"/}"
    else
      error "bash -n failed: ${f#"$REPO"/}"
      printf '%s\n' "$output" >&2
    fi
  done

  if command -v shellcheck >/dev/null 2>&1; then
    if output="$(shellcheck "$REPO/install.sh" 2>&1)"; then
      ok "shellcheck: no warnings in install.sh"
    else
      warn "shellcheck reported issues in install.sh"
      printf '%s\n' "$output" >&2
    fi
  else
    vlog "shellcheck not installed; skipped"
  fi
}

validate_json() {
  log "Validating JSON/JSONC"
  local f output tmp
  while IFS= read -r -d '' f; do
    if output="$(jq empty "$f" 2>&1)"; then
      vlog "jq ok: ${f#"$REPO"/}"
    else
      error "jq failed: ${f#"$REPO"/}"
      printf '%s\n' "$output" >&2
    fi
  done < <(find "$REPO" -path "$REPO/.git" -prune -o -type f -name '*.json' -print0)

  while IFS= read -r -d '' f; do
    if ! command -v python3 >/dev/null 2>&1; then
      warn "python3 missing; cannot validate ${f#"$REPO"/}"
      continue
    fi
    tmp="$(mktemp)"
    TMP_FILES+=("$tmp")
    if python3 - "$f" > "$tmp" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
out = []
i = 0
n = len(text)
in_string = False
escaped = False

while i < n:
    char = text[i]
    nxt = text[i + 1] if i + 1 < n else ""
    if in_string:
        out.append(char)
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = False
        i += 1
        continue
    if char == '"':
        in_string = True
        out.append(char)
        i += 1
        continue
    if char == "/" and nxt == "/":
        while i < n and text[i] not in "\r\n":
            i += 1
        continue
    if char == "/" and nxt == "*":
        i += 2
        while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
            i += 1
        i += 2
        continue
    out.append(char)
    i += 1

sys.stdout.write("".join(out))
PY
    then
      if output="$(jq empty "$tmp" 2>&1)"; then
        vlog "jq ok (JSONC): ${f#"$REPO"/}"
      else
        error "jq failed (JSONC): ${f#"$REPO"/}"
        printf '%s\n' "$output" >&2
      fi
    else
      error "Could not strip comments from ${f#"$REPO"/}"
    fi
  done < <(find "$REPO" -path "$REPO/.git" -prune -o -type f -name '*.jsonc' -print0)
}

validate_lua() {
  log "Validating Lua files"
  if ! command -v luac >/dev/null 2>&1; then
    vlog "luac not installed; skipped"
    return 0
  fi
  local f output
  while IFS= read -r -d '' f; do
    if output="$(luac -p "$f" 2>&1)"; then
      vlog "luac ok: ${f#"$REPO"/}"
    else
      error "luac failed: ${f#"$REPO"/}"
      printf '%s\n' "$output" >&2
    fi
  done < <(find "$REPO/hypr" "$REPO/theme" -type f -name '*.lua' -print0 2>/dev/null)
}

validate_rofi() {
  if ! command -v rofi >/dev/null 2>&1; then
    vlog "rofi not installed; skipped rofi -dump-theme"
    return 0
  fi
  log "Validating Rofi theme"
  local output
  if output="$(rofi -dump-theme -config "$REPO/rofi/.config/rofi/config.rasi" 2>&1 >/dev/null)"; then
    vlog "rofi theme ok"
  else
    error "rofi -dump-theme failed"
    printf '%s\n' "$output" >&2
  fi
}

validate_fonts() {
  if ! command -v fc-match >/dev/null 2>&1; then
    vlog "fc-match not installed; skipped font checks"
    return 0
  fi
  log "Checking fonts (missing optional fonts are warnings)"
  local font family
  for font in "SF Pro Text" "SF Pro Display" "SF Mono" "JetBrainsMono Nerd Font Mono"; do
    family="$(fc-match -f '%{family}' "$font" 2>/dev/null || true)"
    if [[ "$family" == *"$font"* ]]; then
      vlog "font ok: $font"
    else
      warn "Font not found: $font (fc-match resolved to '${family:-nothing}')"
    fi
  done
}

validate_python_gi() {
  if ! command -v python3 >/dev/null 2>&1; then
    vlog "python3 not installed; skipped PyGObject check"
    return 0
  fi
  log "Checking PyGObject GTK3"
  local output
  if output="$(python3 -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0"); from gi.repository import Gtk, Gdk' 2>&1)"; then
    vlog "PyGObject GTK3 ok"
  else
    warn "PyGObject GTK3 not available; waybar-settings may not run"
    printf '%s\n' "$output" >&2
  fi
}

validate_hyprctl() {
  if ! command -v hyprctl >/dev/null 2>&1; then
    vlog "hyprctl not installed; skipped"
    return 0
  fi
  local output
  if output="$(hyprctl configerrors 2>/dev/null)"; then
    if [[ -n "$output" && "$output" != "no errors"* ]]; then
      error "hyprctl configerrors reported problems"
      printf '%s\n' "$output" >&2
    else
      vlog "hyprctl configerrors: clean"
    fi
  else
    vlog "Hyprland is not running; skipped hyprctl configerrors"
  fi
}

validate_waybar_build() {
  log "Validating waybar-build"
  if (( DRY_RUN )); then
    log "[dry-run] skip waybar-build validation"
    return 0
  fi
  run_waybar_build
  local cache="$HOME/.cache/waybar/config.json"
  if [[ -f "$cache" ]]; then
    if jq empty "$cache" >/dev/null 2>&1; then
      vlog "generated Waybar config is valid JSON"
    else
      error "generated Waybar config is not valid JSON: $cache"
    fi
  else
    warn "Waybar config was not generated: $cache"
  fi
}

validate_all() {
  log "Running validation"
  validate_bash_scripts
  validate_json
  validate_lua
  validate_rofi
  validate_fonts
  validate_python_gi
  validate_waybar_build
  validate_hyprctl
}

summary() {
  printf '\n'
  if (( FAILURES > 0 )); then
    printf '%sFinished with %d error(s) and %d warning(s).%s\n' "$C_RED" "$FAILURES" "$WARNINGS" "$C_RESET"
  else
    printf '%sGlasshouse install completed with %d warning(s).%s\n' "$C_GREEN" "$WARNINGS" "$C_RESET"
  fi
  if [[ -d "$BACKUP_ROOT" ]]; then
    printf 'Backups: %s\n' "$BACKUP_ROOT"
    printf 'Manifest: %s\n' "$MANIFEST"
  else
    printf 'No backups were needed.\n'
  fi
  if (( DRY_RUN )); then
    printf 'Dry run: nothing was changed.\n'
  fi
  if (( FAILURES > 0 )); then
    exit 1
  fi
}

main() {
  parse_args "$@"
  banner
  check_repo_location
  check_dependencies

  if (( INSTALL_DESKTOP_DEPS )); then
    install_pkg_profile "desktop" "${DESKTOP_DEPS_PKGS[@]}"
  fi
  if (( INSTALL_SDDM_DEPS )); then
    install_pkg_profile "sddm" "${SDDM_DEPS_PKGS[@]}"
  fi

  if (( ! DRY_RUN )); then
    if ! confirm "Proceed with user-level links and runtime defaults?"; then
      log "Aborted by user"
      exit 0
    fi
  fi

  preserve_theme_runtime
  link_configs
  ensure_pictures
  create_runtime_defaults

  if (( WITH_SESSION )); then
    install_session
  fi
  if (( WITH_FONTS )); then
    install_fonts
  fi
  if (( WITH_SDDM )); then
    install_sddm
  fi

  validate_all
  summary
}

main "$@"
