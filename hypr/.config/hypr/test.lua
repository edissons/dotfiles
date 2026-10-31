-- Entrada de la sesión de prueba (se lanza con hypr-test, con bus D-Bus aislado).
-- Igual que session.lua pero SIN --systemd, para no contaminar la sesión principal.
local dir = os.getenv("HOME") .. "/dotfiles/hypr/.config/hypr"
package.path = dir .. "/?.lua;" .. package.path

require("hyprland")
