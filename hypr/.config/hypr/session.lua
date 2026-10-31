-- Entrada de la sesión "Hyprland (Glass)".
-- Se lanza con:  start-hyprland -- -c ~/dotfiles/hypr/.config/hypr/session.lua
local dir = os.getenv("HOME") .. "/dotfiles/hypr/.config/hypr"
package.path = dir .. "/?.lua;" .. package.path

require("hyprland")

-- Sesión real: publica el entorno para portales y servicios de systemd --user.
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
end)
