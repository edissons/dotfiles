#!/usr/bin/env bash
# ~/.config/powermodemenu/apply-saved-mode.sh
# Re-apply the persisted power mode and idle profile at login.
# Called by powermodemenu-apply.service.
set -u
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/powermodemenu/mode"
HELPER="/usr/local/lib/powermodemenu/powermodemenu-helper"
IDLE="$HOME/.config/powermodemenu/apply-idle-profile"
MODE="automatic"
[ -f "$STATE" ] && MODE=$(tr -d '\r\n' < "$STATE" | head -n1)
case "$MODE" in automatic|low|high|gaming) ;; *) MODE="automatic" ;; esac

# Apply system-level mode (privileged helper)
if [ -x "$HELPER" ]; then
  # Prefer pkexec/sudo -n; helper is privileged
  if command -v pkexec >/dev/null 2>&1; then
    pkexec "$HELPER" apply "$MODE" || sudo -n "$HELPER" apply "$MODE" || true
  else
    sudo -n "$HELPER" apply "$MODE" || true
  fi
fi

# Apply user-session idle (hypridle) profile
[ -x "$IDLE" ] && "$IDLE" || true
