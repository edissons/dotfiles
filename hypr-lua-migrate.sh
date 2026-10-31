#!/usr/bin/env bash
# =============================================================================
# hypr-lua-migrate.sh — migra la configuración de Hyprland de hyprlang (.conf)
# a Lua (Hyprland >= 0.55; en 0.57 el formato .conf ya no se lee).
#
# Qué hace (todo dentro del repo ~/dotfiles, con copia de seguridad previa):
#   1. Convierte con hyprconf2lua los .conf de Hyprland (hyprland.conf, daily.conf...).
#      NO toca hypridle.conf ni hyprlock.conf: son programas distintos y siguen
#      usando hyprlang.
#   2. Arregla lo que el convertidor deja a medias: variables compartidas entre
#      archivos, los `source` (pasan a require) y los colores del tema.
#   3. Genera colors.lua del tema claro/oscuro a partir de colors.conf (una sola
#      fuente de verdad, que además sigue usando hyprlock).
#   4. Crea session.lua (sesión real) y test.lua (sesión de prueba, bus aislado).
#   5. Actualiza los scripts que llaman a `hyprctl dispatch` con la sintaxis
#      antigua (en la era Lua se evalúa como Lua).
#   6. Valida la sintaxis de los .lua generados.
#   7. Instala el lanzador de la sesión con `sudo install` (salvo --no-install).
#   8. Archiva los .conf de Hyprland en hypr/legacy/ (no borra hypridle/hyprlock).
#
# No hace commit. Uso:
#   ./hypr-lua-migrate.sh              # migra e instala el lanzador
#   ./hypr-lua-migrate.sh --force      # vuelve a convertir aunque ya exista el .lua
#   ./hypr-lua-migrate.sh --no-install # migra sin tocar /usr/local/bin
# =============================================================================
set -Eeuo pipefail

REPO="${DOTFILES:-$HOME/dotfiles}"
HYPR="$REPO/hypr/.config/hypr"
LEGACY="$HYPR/legacy"
THEME="$REPO/theme/.config/theme"
THEME_BIN="$REPO/theme/.local/bin"
BIN="$REPO/scripts/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.dotfiles-backup/hypr-lua-$STAMP"
FORCE=0
INSTALL=1

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m  xx\033[0m %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --no-install) INSTALL=0 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

trap 'die "Falló en la línea $LINENO. Tu copia de seguridad está en $BACKUP"' ERR

# --------------------------------------------------------------------------- #
say "Comprobaciones"
[ -d "$HYPR" ] || die "No encuentro $HYPR (puedes indicar otra ruta con DOTFILES=/ruta)"
command -v hyprconf2lua >/dev/null 2>&1 || die \
  "Falta hyprconf2lua >= 1.7.0. Instálalo con pipx o actualiza el clon local."

H2L_VER="$(hyprconf2lua --version 2>&1 | sed -nE 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | sed -n '1p')"
[ -n "$H2L_VER" ] || die "No pude detectar la versión de hyprconf2lua."
if [ "$(printf '%s\n' '1.7.0' "$H2L_VER" | sort -V | sed -n '1p')" != '1.7.0' ]; then
  die "hyprconf2lua v$H2L_VER es demasiado antiguo; necesitas >= 1.7.0. Actualízalo antes de continuar."
fi

LUAC=""
for c in luac luac5.4 luac5.3; do command -v "$c" >/dev/null 2>&1 && { LUAC="$c"; break; }; done
[ -n "$LUAC" ] || warn "No hay luac: se omitirá la validación de sintaxis (sudo pacman -S lua)"
ok "hyprconf2lua v$H2L_VER (>= 1.7.0)"

# --------------------------------------------------------------------------- #
say "Copia de seguridad en $BACKUP"
mkdir -p "$BACKUP/hypr" "$BACKUP/scripts"
cp -a "$HYPR/." "$BACKUP/hypr/"
for s in power-menu hypr-test hyprland-glass; do
  [ -f "$BIN/$s" ] && cp -a "$BIN/$s" "$BACKUP/scripts/"
done
[ -f "$THEME_BIN/theme-toggle" ] && cp -a "$THEME_BIN/theme-toggle" "$BACKUP/scripts/"
ok "hecha"

# --------------------------------------------------------------------------- #
say "Colores del tema (colors.conf -> colors.lua)"
gen_colors_lua() {   # entrada: colors.conf  salida: colors.lua
  awk 'BEGIN { print "-- Generado desde colors.conf (no editar a mano; regenerar con hypr-lua-migrate o theme-lua-gen)."; print "return {" }
       /^\$[A-Za-z0-9_]+[ \t]*=/ {
         name = substr($1, 2)
         sub(/^\$[A-Za-z0-9_]+[ \t]*=[ \t]*/, "", $0)
         sub(/[ \t]+#.*$/, "", $0); sub(/[ \t]+$/, "", $0)
         gsub(/\\/, "\\\\", $0); gsub(/"/, "\\\"", $0)
         printf "  %s = \"%s\",\n", name, $0 }
       END { print "}" }' "$1" > "$2"
}
for mode in dark light; do
  if [ -f "$THEME/$mode/colors.conf" ]; then
    gen_colors_lua "$THEME/$mode/colors.conf" "$THEME/$mode/colors.lua"
    ok "$mode/colors.lua"
  else
    warn "No existe $THEME/$mode/colors.conf"
  fi
done
cur_mode="$(cat "$THEME/mode" 2>/dev/null || echo dark)"
[ -f "$THEME/$cur_mode/colors.lua" ] && ln -sfn "$THEME/$cur_mode/colors.lua" "$THEME/current.lua" \
  && ok "current.lua -> $cur_mode/colors.lua"

# Script para regenerar los colors.lua cuando se edite colors.conf
cat > "$BIN/theme-lua-gen" <<'EOF'
#!/usr/bin/env bash
# Regenera colors.lua (claro y oscuro) a partir de colors.conf.
T="$HOME/dotfiles/theme/.config/theme"
for mode in dark light; do
  [ -f "$T/$mode/colors.conf" ] || continue
  awk 'BEGIN { print "-- Generado desde colors.conf (no editar a mano; regenerar con theme-lua-gen)."; print "return {" }
       /^\$[A-Za-z0-9_]+[ \t]*=/ {
         name = substr($1, 2)
         sub(/^\$[A-Za-z0-9_]+[ \t]*=[ \t]*/, "", $0)
         sub(/[ \t]+#.*$/, "", $0); sub(/[ \t]+$/, "", $0)
         gsub(/\\/, "\\\\", $0); gsub(/"/, "\\\"", $0)
         printf "  %s = \"%s\",\n", name, $0 }
       END { print "}" }' "$T/$mode/colors.conf" > "$T/$mode/colors.lua"
  echo "$mode/colors.lua regenerado"
done
EOF
chmod +x "$BIN/theme-lua-gen"
ok "scripts/.local/bin/theme-lua-gen"

# Bloque Lua que sustituye al `source = ~/.config/theme/current.conf`
CB="$(mktemp)"
{
  echo '-- Colores del tema (claro/oscuro), leídos de ~/.config/theme/current.lua'
  echo 'local _ok, _theme = pcall(dofile, os.getenv("HOME") .. "/.config/theme/current.lua")'
  echo 'if not _ok or type(_theme) ~= "table" then _theme = {} end'
  if [ -f "$THEME/dark/colors.conf" ]; then
    awk '/^\$[A-Za-z0-9_]+[ \t]*=[ \t]*rgba?\(/ {
           name = substr($1, 2); v = $0
           sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
           printf "local %s = _theme.%s or \"%s\"\n", name, name, v }' "$THEME/dark/colors.conf"
  fi
} > "$CB"

# theme-toggle: que también enlace current.lua
if [ -f "$THEME_BIN/theme-toggle" ] && grep -qE 'for f in .*kitty' "$THEME_BIN/theme-toggle" \
   && ! grep -qE 'for f in .*\blua\b' "$THEME_BIN/theme-toggle"; then
  sed -i -E '/for f in .*kitty/ s/kitty/kitty lua/' "$THEME_BIN/theme-toggle"
  ok "theme-toggle enlaza también current.lua"
fi

# --------------------------------------------------------------------------- #
say "Conversión de los .conf de Hyprland"
SRC_DIR="$HYPR"
if [ ! -f "$HYPR/hyprland.conf" ] && [ -f "$LEGACY/hyprland.conf" ]; then
  SRC_DIR="$LEGACY"
fi
share_vars() {   # añade a $1 las definiciones $var que usa pero define en hyprland.conf
  local f="$1" main="$SRC_DIR/hyprland.conf" v name def prelude=""
  [ -f "$main" ] || return 0
  for v in $(grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' "$f" | sort -u); do
    name="${v#\$}"
    grep -qE "^[[:space:]]*[\$]${name}[[:space:]]*=" "$f" && continue
    def="$(grep -m1 -E "^[[:space:]]*[\$]${name}[[:space:]]*=" "$main" || true)"
    [ -n "$def" ] && prelude+="$def"$'\n'
  done
  if [ -n "$prelude" ]; then
    printf '%s\n' "$prelude" | cat - "$f" > "$f.new" && mv "$f.new" "$f"
  fi
}

converted=()
for src in "$SRC_DIR"/*.conf; do
  [ -e "$src" ] || continue
  name="$(basename "$src" .conf)"
  case "$name" in
    hypridle|hyprlock|session) continue ;;   # otros programas / reemplazado por session.lua
  esac
  out="$HYPR/$name.lua"
  if [ -f "$out" ] && [ "$FORCE" = 0 ]; then
    warn "$name.lua ya existe: se omite (usa --force para regenerarlo)"
    continue
  fi
  tmp="$(mktemp)"; cp "$src" "$tmp"
  [ "$name" != hyprland ] && share_vars "$tmp"
  if ! hyprconf2lua --check "$tmp" >/dev/null 2>&1; then
    warn "$name.conf: hyprconf2lua marcó directivas para revisión manual"
  fi
  hyprconf2lua "$tmp" -o "$out"
  rm -f "$tmp"
  converted+=("$out")
  ok "$name.conf -> $name.lua"
done

say "Retoques posteriores"
for f in "${converted[@]}"; do
  # 1) el `source` del tema -> bloque de colores
  CB_FILE="$CB" perl -0pi -e '
    BEGIN { open(F, "<", $ENV{CB_FILE}); local $/; $b = <F>; close(F); }
    s/-- source = [^\n]*theme\/current\.conf[^\n]*\n-- local [^\n]*\n-- TODO:[^\n]*\n/$b/s;
  ' "$f"
  # 2) los demás `source` -> require, si el .lua correspondiente existe
  HYPR_DIR="$HYPR" perl -0pi -e '
    s{-- source = [^\n]*?([A-Za-z0-9_.-]+)\.conf -> requires manual conversion\n-- local \w+ = require\("([^"]+)"\)\n-- TODO:[^\n]*\n}
     { (-e "$ENV{HYPR_DIR}/$2.lua") ? "require(\"$2\")\n" : $& }ge;
  ' "$f"
  # 3) rutas con el HOME del usuario -> os.getenv("HOME") (repo portable)
  H="$HOME" perl -0pi -e 's|"\Q$ENV{H}\E/|os.getenv("HOME") .. "/|g' "$f"
  ok "$(basename "$f")"
done
rm -f "$CB"

# --------------------------------------------------------------------------- #
say "Archivos de entrada: session.lua y test.lua"
cat > "$HYPR/session.lua" <<'EOF'
-- Entrada de la sesión "Hyprland (Glass)".
-- Se lanza con:  start-hyprland -- -c ~/dotfiles/hypr/.config/hypr/session.lua
local dir = os.getenv("HOME") .. "/dotfiles/hypr/.config/hypr"
package.path = dir .. "/?.lua;" .. package.path

require("hyprland")

-- Sesión real: publica el entorno para portales y servicios de systemd --user.
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
end)
EOF
cat > "$HYPR/test.lua" <<'EOF'
-- Entrada de la sesión de prueba (se lanza con hypr-test, con bus D-Bus aislado).
-- Igual que session.lua pero SIN --systemd, para no contaminar la sesión principal.
local dir = os.getenv("HOME") .. "/dotfiles/hypr/.config/hypr"
package.path = dir .. "/?.lua;" .. package.path

require("hyprland")
EOF
ok "session.lua y test.lua"

# --------------------------------------------------------------------------- #
say "Scripts: hyprctl dispatch con sintaxis Lua"
cat > "$BIN/hypr-test" <<'EOF'
#!/usr/bin/env bash
# Sesión de prueba con bus D-Bus aislado (no interfiere con la sesión principal).
exec dbus-run-session start-hyprland -- -c "$HOME/dotfiles/hypr/.config/hypr/test.lua"
EOF
chmod +x "$BIN/hypr-test"
ok "hypr-test -> test.lua"

if [ -f "$BIN/hyprland-glass" ]; then
  sed -i 's|session\.conf|session.lua|g' "$BIN/hyprland-glass"
  ok "hyprland-glass -> session.lua"
fi
if [ -f "$BIN/power-menu" ]; then
  perl -pi -e 's/hyprctl dispatch exit/hyprctl dispatch \x27hl.dsp.exit()\x27/g' "$BIN/power-menu"
  ok "power-menu: cerrar sesión"
fi
if [ -f "$HYPR/hypridle.conf" ]; then
  perl -pi -e 's/hyprctl dispatch dpms (on|off)/hyprctl dispatch \x27hl.dsp.dpms({action = "$1"})\x27/g' "$HYPR/hypridle.conf"
  ok "hypridle.conf: dpms"
fi

left="$(grep -rnI "hyprctl dispatch" "$REPO" --exclude-dir=.git --exclude-dir=legacy --exclude=hypr-lua-migrate.sh 2>/dev/null | grep -v "hl\.dsp" | grep -v "^$REPO/README.md" || true)"
if [ -n "$left" ]; then
  warn "Quedan llamadas a 'hyprctl dispatch' con sintaxis antigua; revísalas a mano:"
  printf '%s\n' "$left" >&2
fi

# --------------------------------------------------------------------------- #
say "Validación"
bad=0
if [ -n "$LUAC" ]; then
  for f in "$HYPR"/*.lua "$THEME"/dark/colors.lua "$THEME"/light/colors.lua; do
    [ -f "$f" ] || continue
    if "$LUAC" -p "$f" 2>/tmp/luac.err; then ok "sintaxis $(basename "$(dirname "$f")")/$(basename "$f")"
    else warn "ERROR de sintaxis en $f: $(cat /tmp/luac.err)"; bad=1; fi
  done
fi
todo="$(grep -n "TODO" "$HYPR"/*.lua 2>/dev/null || true)"
if [ -n "$todo" ]; then warn "Quedan marcas TODO por revisar a mano:"; printf '%s\n' "$todo" >&2; fi

[ "$bad" = 0 ] || exit 2

say "Archivando .conf antiguos en legacy/"
mkdir -p "$LEGACY"
for n in hyprland daily session; do
  if [ -f "$HYPR/$n.conf" ] && [ -f "$HYPR/$n.lua" ]; then
    mv "$HYPR/$n.conf" "$LEGACY/$n.conf"
    ok "$n.conf -> legacy/$n.conf"
  fi
done

if [ "$INSTALL" = 1 ]; then
  say "Instalando lanzador de sesión"
  command -v sudo >/dev/null 2>&1 || die "Falta sudo para instalar /usr/local/bin/hyprland-glass."
  sudo install -m 755 "$BIN/hyprland-glass" /usr/local/bin/hyprland-glass \
    || die "No se pudo instalar /usr/local/bin/hyprland-glass."
  ok "/usr/local/bin/hyprland-glass -> session.lua"
else
  warn "Instalación del lanzador omitida (--no-install)."
fi

cat <<EOF

────────────────────────────────────────────────────────────────
Listo. Copia de seguridad: $BACKUP

Siguientes pasos:
  1. Revisa el resultado:   git -C "$REPO" status && less "$HYPR/hyprland.lua"
  2. El lanzador de la sesión ya apunta a session.lua.
     Si usaste --no-install, instálalo manualmente:
       sudo install -m 755 "$BIN/hyprland-glass" /usr/local/bin/hyprland-glass
  3. Pruébalo SIN tocar tu sesión actual: en otro TTY (Ctrl+Alt+F3):  hypr-test
     Dentro: hyprctl configerrors   (debe salir vacío)
  4. Si todo va bien, cierra sesión y entra en "Hyprland (Glass)".
  5. Los .conf antiguos quedaron en legacy/. Cuando esté validado, haz commit.
────────────────────────────────────────────────────────────────
EOF
