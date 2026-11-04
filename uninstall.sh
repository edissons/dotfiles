#!/usr/bin/env bash
#
# Glasshouse dotfiles uninstaller
#
# What it does:
#   Removes only the user-level symlinks that install.sh created inside $HOME
#   and whose resolved target is inside this repository. It then restores the
#   files recorded in an install manifest (target<TAB>backup), but only when
#   the destination is absent or is still a repository symlink. Regular files,
#   real directories, foreign symlinks, runtime theme data, caches and system
#   changes (SDDM, fonts, /usr/local) are never deleted.
#
# Dependencies:
#   bash >= 4.4, coreutils (basename, dirname, readlink, realpath, rm, cp,
#   mkdir). No sudo and no network access are required.
#
# Usage:
#   ./uninstall.sh [--dry-run] [--yes] [--backup PATH]
#   ./uninstall.sh --help
#
# Backup selection:
#   --backup PATH selects an explicit ~/.dotfiles-backup/install-* directory.
#   Without it, the newest ~/.dotfiles-backup/install-* directory is used.
#   If no backup exists, links are still removed and restoration is skipped.
#
# Safety:
#   --dry-run prints the plan and writes nothing.
#   --yes skips the final confirmation prompt.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$SCRIPT_DIR"
REPO_REAL="$(readlink -f -- "$REPO" 2>/dev/null || true)"
[[ -n "$REPO_REAL" ]] || REPO_REAL="$REPO"

DRY_RUN=0
ASSUME_YES=0
BACKUP_ARG=""
BACKUP_DIR=""
MANIFEST=""

REMOVED=()
RESTORED=()
SKIPPED=()
declare -A REMOVED_SET=()
WARNINGS=0
FAILURES=0

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

die() {
  error "$*"
  exit 1
}

banner() {
  printf '\n'
  printf '%s' "$C_BOLD"
  cat <<'EOF'
   ____ _                _
  / ___| | __ _ ___ ___ | |__  _   _  ___  ___
 | |  _| |/ _` / __/ __|| '_ \| | | |/ _ \/ __|
 | |_| | | (_| \__ \__ \| | | | |_| |  __/\__ \
  \____|_|\__,_|___/___/|_| |_|\__,_|\___||___/
EOF
  printf '%s' "$C_RESET"
  printf '  Glasshouse dotfiles uninstaller\n'
  printf '  repo: %s\n' "$REPO"
  printf '  home: %s\n\n' "$HOME"
}

usage() {
  cat <<'EOF'
Glasshouse dotfiles uninstaller

Removes only symlinks whose resolved target is inside this repository and
restores files from an install backup manifest when it is safe to do so.
Regular files, real directories, foreign symlinks, runtime theme data and
system-level changes are never removed.

Flags:
  --dry-run        Show every action without changing anything.
  --yes, -y        Do not ask for the final confirmation.
  --backup PATH    Use this install backup directory instead of the newest
                   ~/.dotfiles-backup/install-* directory.
  -h, --help       Show this help.

What is cleaned (only if it is a symlink into this repo):
  ~/.config/theme
  ~/.config/nwg-dock-hyprland
  ~/.config/kitty/kitty.conf
  ~/.config/fastfetch/config.jsonc
  ~/.local/bin/<name> for every scripts/.local/bin/<name>
  ~/.local/bin/theme-toggle
  ~/Pictures
  ~/Pictures/wallpapers

Backups are restored only when the destination is absent or is still a
repository symlink. Restoring uses cp -a to preserve permissions. A real file,
a real directory or a symlink pointing outside the repo causes a warning and is
left untouched.

Examples:
  ./uninstall.sh --dry-run
  ./uninstall.sh --yes
  ./uninstall.sh --yes --backup "$HOME/.dotfiles-backup/install-20260101-120000"
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --backup)
        if (($# < 2)) || [[ -z "$2" || "$2" == --* ]]; then
          die "--backup requires a directory path"
        fi
        BACKUP_ARG="$2"
        shift
        ;;
      --backup=*)
        BACKUP_ARG="${1#*=}"
        if [[ -z "$BACKUP_ARG" ]]; then
          die "--backup requires a directory path"
        fi
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        if (($# > 0)); then
          die "Unexpected argument: $1 (use --help)"
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
  local answer

  if ((ASSUME_YES || DRY_RUN)); then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "$prompt (no TTY; re-run with --yes to allow it)"
    return 1
  fi
  read -r -p "$prompt [y/N] " answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

expand_tilde() {
  local path="$1"
  local tilde='~'
  case "$path" in
    "$tilde") printf '%s' "$HOME" ;;
    "$tilde"/*) printf '%s/%s' "$HOME" "${path#"$tilde"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

is_inside_repo() {
  local path="$1"
  case "$path" in
    "$REPO_REAL"|"$REPO_REAL"/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_under_home() {
  local path="$1"
  case "$path" in
    "$HOME"/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_link_target() {
  local path="$1"
  local resolved raw base

  resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    raw="$(readlink -- "$path" 2>/dev/null || true)"
    if [[ -n "$raw" ]]; then
      if [[ "$raw" != /* ]]; then
        base="$(dirname -- "$path")"
        raw="$base/$raw"
      fi
      resolved="$(realpath -m -- "$raw" 2>/dev/null || true)"
    fi
  fi
  printf '%s' "$resolved"
}

record_skip() {
  local message="$1"
  SKIPPED+=("$message")
  warn "$message"
}

remove_repo_link() {
  local path="$1"
  local resolved

  if [[ ! -L "$path" ]]; then
    if [[ -e "$path" ]]; then
      record_skip "$path exists but is not a symlink; left untouched"
    fi
    return 0
  fi

  if ! is_under_home "$path"; then
    record_skip "$path is outside HOME; refusing to remove it"
    return 0
  fi

  resolved="$(resolve_link_target "$path")"
  if [[ -z "$resolved" ]]; then
    record_skip "$path is an unreadable symlink; left untouched"
    return 0
  fi
  if ! is_inside_repo "$resolved"; then
    record_skip "$path -> $resolved is outside the repo; left untouched"
    return 0
  fi

  # Dry-run leaves the link in place, so avoid counting it again when a
  # manifest entry later asks to restore the same target.
  if [[ -n "${REMOVED_SET[$path]:-}" ]]; then
    return 0
  fi
  REMOVED_SET["$path"]=1

  if ((DRY_RUN)); then
    log "[dry-run] would remove link: $path -> $resolved"
  else
    rm -f -- "$path"
    log "Removed link: $path"
  fi
  REMOVED+=("$path -> $resolved")
}

remove_known_links() {
  local f name

  log "Removing Glasshouse links (only symlinks into the repo)"

  remove_repo_link "$HOME/.config/theme"
  remove_repo_link "$HOME/.config/nwg-dock-hyprland"
  remove_repo_link "$HOME/.config/kitty/kitty.conf"
  remove_repo_link "$HOME/.config/fastfetch/config.jsonc"

  for f in "$REPO"/scripts/.local/bin/*; do
    [[ -f "$f" ]] || continue
    name="$(basename -- "$f")"
    remove_repo_link "$HOME/.local/bin/$name"
  done

  remove_repo_link "$HOME/.local/bin/theme-toggle"

  # If Pictures itself is a repo symlink, removing it removes the wallpapers
  # path too. If Pictures is a real directory, only clean its wallpapers link.
  if [[ -L "$HOME/Pictures" ]]; then
    remove_repo_link "$HOME/Pictures"
  elif [[ -d "$HOME/Pictures" ]]; then
    remove_repo_link "$HOME/Pictures/wallpapers"
  elif [[ -e "$HOME/Pictures" ]]; then
    record_skip "$HOME/Pictures exists but is not a directory; left untouched"
  fi
}

latest_install_backup() {
  local base="$HOME/.dotfiles-backup"
  local candidate latest=""

  if [[ ! -d "$base" ]]; then
    printf '%s' ""
    return 0
  fi

  for candidate in "$base"/install-*; do
    [[ -d "$candidate" ]] || continue
    if [[ -z "$latest" || "$candidate" > "$latest" ]]; then
      latest="$candidate"
    fi
  done
  printf '%s' "$latest"
}

select_backup() {
  local arg="${1:-}"

  if [[ -n "$arg" ]]; then
    BACKUP_DIR="$(expand_tilde "$arg")"
    if [[ ! -d "$BACKUP_DIR" ]]; then
      die "Backup directory not found: $BACKUP_DIR"
    fi
    MANIFEST="$BACKUP_DIR/manifest.txt"
    if [[ ! -f "$MANIFEST" ]]; then
      die "Install manifest not found: $MANIFEST"
    fi
    return 0
  fi

  BACKUP_DIR="$(latest_install_backup)"
  if [[ -n "$BACKUP_DIR" ]]; then
    MANIFEST="$BACKUP_DIR/manifest.txt"
    if [[ ! -f "$MANIFEST" ]]; then
      warn "Latest backup has no manifest: $BACKUP_DIR (skipping restore)"
      MANIFEST=""
    fi
  else
    MANIFEST=""
  fi
}

restore_entry() {
  local target="$1"
  local backup="$2"
  local parent resolved

  if [[ ! -e "$backup" && ! -L "$backup" ]]; then
    record_skip "Backup is missing for $target: $backup"
    return 0
  fi

  parent="$(realpath -m -- "$(dirname -- "$target")" 2>/dev/null || true)"
  if [[ -z "$parent" ]] || { [[ "$parent" != "$HOME" ]] && ! is_under_home "$parent"; }; then
    record_skip "Refusing to restore outside HOME: $target"
    return 0
  fi

  if [[ -L "$target" ]]; then
    resolved="$(resolve_link_target "$target")"
    if [[ -n "$resolved" ]] && is_inside_repo "$resolved"; then
      remove_repo_link "$target"
    else
      record_skip "Cannot restore $target: current symlink is outside the repo (${resolved:-unknown})"
      return 0
    fi
  elif [[ -e "$target" ]]; then
    record_skip "Cannot restore $target: target exists and is not a repo symlink"
    return 0
  fi

  if ((! DRY_RUN)) && [[ -e "$target" || -L "$target" ]]; then
    # remove_repo_link already recorded why it was not removed.
    return 0
  fi

  if ((DRY_RUN)); then
    log "[dry-run] would restore: $backup -> $target"
  else
    mkdir -p -- "$(dirname -- "$target")"
    if cp -a -- "$backup" "$target"; then
      log "Restored: $target (from $backup)"
    else
      error "Failed to restore $target from $backup"
      return 0
    fi
  fi
  RESTORED+=("$target (from $backup)")
}

restore_manifest() {
  local manifest="$1"
  local line target backup saw_header=0
  local -A seen=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    if ((! saw_header)); then
      if [[ "$line" == "target"$'\t'"backup" ]]; then
        saw_header=1
      fi
      continue
    fi

    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" != *$'\t'* ]]; then
      record_skip "Malformed manifest line: $line"
      continue
    fi

    target="${line%%$'\t'*}"
    backup="${line#*$'\t'}"

    if [[ -z "$target" || -z "$backup" ]]; then
      record_skip "Malformed manifest line: $line"
      continue
    fi
    if ! is_under_home "$target"; then
      record_skip "Manifest target is outside HOME: $target"
      continue
    fi
    if [[ -n "${seen[$target]:-}" ]]; then
      record_skip "Duplicate manifest entry for $target; skipping"
      continue
    fi
    seen["$target"]=1

    restore_entry "$target" "$backup"
  done < "$manifest"

  if ((! saw_header)); then
    warn "Manifest has no target<TAB>backup header: $manifest"
  fi
}

summary() {
  local remove_verb="Removed"
  local restore_verb="Restored"

  if ((DRY_RUN)); then
    remove_verb="Would remove"
    restore_verb="Would restore"
  fi

  printf '\n'
  printf '%sGlasshouse uninstall summary%s\n' "$C_BOLD" "$C_RESET"
  printf '  Repo: %s\n' "$REPO"
  if [[ -n "$BACKUP_DIR" ]]; then
    printf '  Backup location: %s\n' "$BACKUP_DIR"
    if [[ -n "$MANIFEST" ]]; then
      printf '  Manifest: %s\n' "$MANIFEST"
    fi
  else
    printf '  Backup location: none found\n'
  fi

  printf '  %s links: %d\n' "$remove_verb" "${#REMOVED[@]}"
  if ((${#REMOVED[@]} > 0)); then
    printf '    - %s\n' "${REMOVED[@]}"
  fi

  printf '  %s backups: %d\n' "$restore_verb" "${#RESTORED[@]}"
  if ((${#RESTORED[@]} > 0)); then
    printf '    - %s\n' "${RESTORED[@]}"
  fi

  printf '  Skipped items: %d\n' "${#SKIPPED[@]}"
  if ((${#SKIPPED[@]} > 0)); then
    printf '    - %s\n' "${SKIPPED[@]}"
  fi

  if ((WARNINGS > 0)); then
    printf '  Warnings: %d\n' "$WARNINGS"
  fi
  if ((FAILURES > 0)); then
    printf '  Failures: %d\n' "$FAILURES"
  fi
  if ((DRY_RUN)); then
    printf '  Dry run: nothing was changed.\n'
  fi
  printf '\n'

  if ((FAILURES > 0)); then
    exit 1
  fi
}

main() {
  parse_args "$@"
  banner
  select_backup "$BACKUP_ARG"

  if [[ -n "$BACKUP_DIR" ]]; then
    log "Backup restore source: $BACKUP_DIR"
  else
    log "Backup restore source: none found"
  fi

  if ((! DRY_RUN)); then
    if ! confirm "Remove Glasshouse symlinks and restore available backups?"; then
      log "Aborted; nothing was changed."
      exit 0
    fi
  fi

  remove_known_links

  if [[ -n "$MANIFEST" && -f "$MANIFEST" ]]; then
    log "Restoring backups listed in $MANIFEST"
    restore_manifest "$MANIFEST"
  else
    warn "No install manifest selected; skipping backup restore"
  fi

  ok "Uninstall pass finished"
  summary
}

main "$@"
