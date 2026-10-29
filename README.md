# dotfiles

Configuración personal de Arch Linux + Hyprland con estética macOS/Liquid Glass.
Incluye Hyprland, Hyprlock, Hypridle, Waybar, SwayNC, Rofi, nwg-dock-hyprland,
Kitty, tema SDDM propio y un sistema de tema claro/oscuro compartido.

## Arquitectura

La sesión activa usa la configuración del repo, no `~/.config/hypr`:

```text
/usr/local/bin/hyprland-glass
  -> start-hyprland -- -c ~/dotfiles/hypr/.config/hypr/session.conf
```

Archivos y rutas activas:

- `~/dotfiles/hypr/.config/hypr/session.conf`: entrada real de la sesión.
- `~/dotfiles/hypr/.config/hypr/hyprland.conf`: configuración base.
- `~/dotfiles/hypr/.config/hypr/daily.conf`: atajos y servicios de sesión.
- `~/dotfiles/hypr/.config/hypr/hypridle.conf`: bloqueo y suspensión.
- `~/dotfiles/hypr/.config/hypr/hyprlock.conf`: lockscreen.
- `~/.config/theme -> ~/dotfiles/theme/.config/theme`: colores y modo.
- `~/.config/nwg-dock-hyprland -> ~/dotfiles/nwg-dock-hyprland/.config/nwg-dock-hyprland`.
- `~/.local/bin/* -> ~/dotfiles/scripts/.local/bin/*`: scripts.
- Waybar usa `~/.cache/waybar/config.json` generado por `waybar-build` y
  `~/dotfiles/waybar/.config/waybar/style.css`.
- SwayNC se lanza con `-c`/`-s` apuntando al repo.
- Rofi, Kitty y nwg-dock se lanzan con rutas explícitas del repo.

`~/.config/hypr` contiene configuraciones HyDE antiguas y no es la configuración
activa. No editar allí esperando cambios en la sesión.

## Dependencias principales

```text
hyprland hyprlock hypridle waybar swaync nwg-dock-hyprland
rofi kitty sddm qt5-quickcontrols2 qt5-graphicaleffects
jq networkmanager brightnessctl pamixer playerctl grim slurp
wl-clipboard cliphist swaybg
```

Fuentes:

- `SF Pro Text`, `SF Pro Display`, `SF Pro Rounded` y `SF Pro`.
- `JetBrainsMono Nerd Font` y `JetBrainsMono Nerd Font Mono`.
- `Inter` sigue instalada como respaldo, pero ya no es la fuente principal.

SF Pro no se versiona en el repo. La copia usada está en:

```text
~/.local/share/fonts/San-Francisco-Pro-Fonts-master/
```

## Instalación de symlinks

Si faltan en un equipo nuevo:

```bash
ln -sfn ~/dotfiles/theme/.config/theme ~/.config/theme
ln -sfn ~/dotfiles/nwg-dock-hyprland/.config/nwg-dock-hyprland ~/.config/nwg-dock-hyprland
for f in ~/dotfiles/scripts/.local/bin/*; do
  ln -sfn "$f" "$HOME/.local/bin/$(basename "$f")"
done
```

## Fuentes

### Sesión de usuario

`fonts-apply` aplica las fuentes en la sesión y guarda backups con sufijo
`.bak.<fecha>`:

```bash
~/.local/bin/fonts-apply
```

Cambios que aplica:

- `gsettings`:
  - `font-name = SF Pro Text 10`
  - `document-font-name = SF Pro Text 10`
  - `monospace-font-name = JetBrainsMono Nerd Font Mono 10`
  - `titlebar-font = SF Pro Display 11`
- `~/.config/gtk-3.0/settings.ini`:
  - `gtk-font-name=SF Pro Text 10`
- `~/.config/gtk-4.0/settings.ini`:
  - `gtk-font-name=SF Pro Text 10`
- `~/.config/qt5ct/qt5ct.conf` y `~/.config/qt6ct/qt6ct.conf`:
  - `general` usa `SF Pro Text`.
  - `fixed` usa `JetBrainsMono Nerd Font Mono`.

GTK3/GTK4 solo admiten `gtk-font-name` en `settings.ini`; no se añade
`gtk-monospace-font-name` porque GTK lo rechaza con un warning. La fuente
monoespaciada se aplica vía `gsettings` y vía Qt.

### SDDM

El greeter corre como el usuario `sddm`, así que no ve las fuentes de
`~/.local/share/fonts`. Para que el tema glass use SF Pro de verdad hay que
instalarlas a nivel de sistema:

```bash
~/.local/bin/fonts-install
```

El script copia los 47 archivos `.otf`/`.ttf` del master de SF Pro a:

```text
/usr/local/share/fonts/sf-pro/
```

Después ejecuta `fc-cache -f` y verifica la resolución como usuario y como
`sddm`:

```bash
sudo -u sddm fc-match -f '%{family} | %{style} | %{file}\n' "SF Pro Text"
```

No se borra ninguna fuente existente. El duplicado
`~/.local/share/fonts/SF Pro Display` se deja intacto; contiene 9 estilos que
también están en el master. `fc-match` puede elegir ese duplicado, pero ambos
son válidos.

## Lockscreen

El bloqueo se lanza con:

```bash
~/.local/bin/lock-screen
```

`lock-screen` genera `~/.cache/hyprlock-run.conf` sustituyendo `@WALL@` por el
fondo actual y `@STATUS@` por el estado de `lock-info`, y luego ejecuta
`hyprlock` con ese archivo. No editar el archivo de caché; editar
`hypr/.config/hypr/hyprlock.conf` y volver a bloquear.

Cambios realizados:

- El texto de estado usa `JetBrainsMono Nerd Font Mono` mediante
  `$font_icons`.
- El glifo wifi `U+F05A9` de la variante no Mono tiene más tinta que avance
  (`advance=600`, `ink.xMax=898`), y hyprlock recortaba el extremo. La variante
  Mono tiene overhang 0, así que el icono se ve completo.
- La hora usa `SF Pro Display` con Pango
  `<span font_weight="600">$TIME</span>`. Hyprlock no expone `font_weight` como
  opción, así que el peso se selecciona con markup. Antes `Inter Bold` podía
  caer en una fuente de respaldo.
- Fecha, inicial, nombre y ayuda usan `SF Pro Display`/`SF Pro Text` según el
  tamaño y el rol.
- El campo de contraseña usa `$font_ui`.
- El lockscreen sigue el tema claro/oscuro con variables de `colors.conf`:
  `$text`, `$subtext`, `$bg`, `$border_active`, `$accent`, `$red`, `$shadow` y
  `$lock_bg_brightness`.
- El fondo es el wallpaper actual (`@WALL@`), no una captura del escritorio.
  `blur_passes` queda en 0 para evitar recapturas y artefactos.

Variables añadidas a `theme/.config/theme/{dark,light}/colors.conf`:

```text
$font_ui = SF Pro Text
$font_display = SF Pro Display
$font_icons = JetBrainsMono Nerd Font Mono
$lock_bg_brightness = 0.85   # dark
$lock_bg_brightness = 1.0    # light
$shadow = rgba(00000066)     # dark
$shadow = rgba(00000033)     # light
$red = rgba(ff453aff)        # dark
$red = rgba(ff3b30ff)        # light
```

`lock-info` se versiona con el repo y es requerido por `lock-screen`.

## SDDM

El tema está en `sddm/glass` y se instala en
`/usr/share/sddm/themes/glass` con:

```bash
~/.local/bin/sddm-install dark
```

### Causa del tema anterior

En esta versión de SDDM el orden de precedencia es:

```text
/usr/lib/sddm/sddm.conf.d
  -> /etc/sddm.conf.d
  -> /etc/sddm.conf        (último, mayor prioridad)
```

`/etc/sddm.conf` contenía `Current=sddm-astronaut-theme`, así que anulaba
`/etc/sddm.conf.d/zz-glass.conf` (`Current=glass`). El journal confirmaba la
carga de `sddm-astronaut-theme/Themes/cyberpunk.conf`.

`fonts-apply`/`sddm-install` no eliminan el tema anterior. `sddm-install`:

- Hace backup del tema instalado en
  `/var/backups/sddm-themes/glass.<fecha>`.
- Copia el tema del repo sin `rm -rf`.
- Copia el wallpaper actual como `background.<ext>`.
- Actualiza `background` y `mode` en `theme.conf`.
- Hace backup de `/etc/sddm.conf` y fija `Current=glass`.
- Hace backup de `/etc/sddm.conf.d/the_hyde_project.conf` y cambia su
  `Current=Candy` por `Current=glass`.
- Mantiene `zz-glass.conf` como está.
- Comprueba si el usuario `sddm` resuelve `SF Pro Text` y avisa si falta
  `fonts-install`.
- No reinicia SDDM; hay que reiniciar el equipo para ver el greeter real.

`/etc/sddm.conf` es el archivo de mayor prioridad. El tema
`sddm-astronaut-theme` sigue instalado, pero ya no se selecciona.

En esta versión, `sddm --example-config` imprime la configuración por defecto y
no refleja la combinación de `/etc/sddm.conf*`. Para verificar el tema real:

```bash
journalctl -u sddm -b --no-pager | grep -Ei 'theme|qml|error|warning' | tail -50
```

Se espera una línea de carga de
`/usr/share/sddm/themes/glass/theme.conf`.

### Fuentes del tema

- `sddm/glass/theme.conf`:
  - `font=SF Pro Text`
  - `fontDisplay=SF Pro Display`
- `sddm/glass/Main.qml`:
  - `root.fam` usa `SF Pro Text` para interfaz, contraseña, sesión, energía y
    menú.
  - `root.famDisplay` usa `SF Pro Display` para reloj, fecha grande, nombre e
    inicial.
  - Si `config.fontDisplay` no está expuesto, el fallback es `SF Pro Display`.
  - Es compatible con Qt5: `import QtQuick 2.15`,
    `import QtQuick.Controls 2.15` e `import QtGraphicalEffects 1.0`.
  - El fondo usa `FastBlur` de QtGraphicalEffects; no usa `QtQuick.Effects`
    ni `MultiEffect`, que son Qt6.

El paquete `sddm 0.21.0-8` de CachyOS lanza `/usr/bin/sddm-greeter`, que está
enlazado contra Qt5, no `sddm-greeter-qt6`. Por eso el tema debe usar imports
con versión. El error:

```text
Library import requires a version
```

aparece cuando un greeter Qt5 carga `import QtQuick` sin versión. La prueba
anterior con `sddm-greeter-qt6` no representaba al greeter real.

Prueba visual sin tocar el sistema:

```bash
TMP="$(mktemp -d)"
cp -r ~/dotfiles/sddm/glass/. "$TMP/"
cp ~/Pictures/wallpapers/332314.jpg "$TMP/background.jpg"
sed -i 's|^background=.*|background=background.jpg|' "$TMP/theme.conf"
sddm-greeter --test-mode --theme "$TMP"
```

El test mode corre como el usuario actual; no demuestra por sí solo que el
usuario `sddm` vea SF Pro. Para eso está `fonts-install` y la verificación con
`sudo -u sddm fc-match`.

Si el tema ya estaba instalado antes de corregir el QML, volver a copiarlo y
reiniciar:

```bash
~/.local/bin/sddm-install dark
systemctl reboot
```

## Waybar

Archivo: `waybar/.config/waybar/style.css`.

- Fuente global: `"SF Pro Text", "JetBrainsMono Nerd Font Mono"`.
- `#clock`: `SF Pro Text`, peso 500.
- `#window`: `SF Pro Display`, peso 500.
- Los iconos Nerd usan el fallback Mono.
- El resto de módulos heredan la fuente global.

La configuración se genera con:

```bash
~/.local/bin/waybar-build
~/.local/bin/waybar-restart
```

`waybar-build` combina `modules.json` y `definitions.json` en
`~/.cache/waybar/config.json`. `modules.json` desactiva `temperature`,
`bluetooth` y `network`.

## SwayNC

Archivo: `swaync/.config/swaync/style.css`.

- Fuente global: `"SF Pro Text", "JetBrainsMono Nerd Font Mono"`.
- `.widget-title`: `SF Pro Display`.
- `.summary`: mantiene `font-weight: 600`.
- Los glifos Nerd caen en la Mono.

Recargar:

```bash
swaync-client -rs
```

## Rofi

Archivos: `rofi/.config/rofi/config.rasi` y `power.rasi`.

- Lanzador: `font: "SF Pro Text 13"`.
- Menú de energía: `font: "SF Pro Text 10"` y `textbox` con el mismo tamaño.
- El `icon-theme` sigue fijado a `WhiteSur-dark`; no se cambió en esta fase.
  Es una inconsistencia conocida con `theme-toggle`, que usa
  `WhiteSur-glass`/`WhiteSur-glass-light`.

Probar:

```bash
rofi -show drun -config ~/dotfiles/rofi/.config/rofi/config.rasi
```

## nwg-dock, Kitty y Hyprland

- nwg-dock hereda la fuente GTK (`SF Pro Text 10`); no se añadió
  `font-family` a su CSS.
- Kitty sigue con `JetBrainsMono Nerd Font` tamaño 11. Es una monoespaciada
  deliberada; no se usa SF Pro en la terminal.
- Hyprland no dibuja títulos de ventana. Los títulos visibles los pinta Waybar
  con `SF Pro Display`; las apps GTK/Qt usan `fonts-apply`.

Recargar el dock:

```bash
~/.local/bin/dock-restart
```

## Tema claro/oscuro

`theme-toggle` cambia los symlinks `current.conf`, `current.css`, `current.rasi`
y `current.kitty`, además de GTK, iconos, Kvantum, Waybar, SwayNC, Kitty y
nwg-dock:

```bash
~/.local/bin/theme-toggle        # alterna
~/.local/bin/theme-toggle dark
~/.local/bin/theme-toggle light
```

El lockscreen sigue el modo porque lee `~/.config/theme/current.conf`.
SDDM es independiente: su modo se define en `sddm/glass/theme.conf` y se puede
cambiar con `sddm-install dark|light` o desde el menú del greeter (solo para esa
sesión).

Pendientes conocidos de integración visual, no tocados en esta fase:

- Rofi fija `WhiteSur-dark` y no sigue el modo claro/oscuro.
- Qt5ct/Qt6ct usan `Tela-circle-dracula` como icon theme.
- `theme-toggle` no actualiza el tema/iconos de GTK4, solo `fonts-apply` toca su
  fuente.

## Scripts

- `scripts/.local/bin/lock-screen`: genera el config de hyprlock y bloquea.
- `scripts/.local/bin/lock-info`: fecha, nombre, inicial y estado.
- `scripts/.local/bin/fonts-apply`: fuentes de usuario (GTK/Qt/gsettings).
- `scripts/.local/bin/fonts-install`: SF Pro system-wide para SDDM.
- `scripts/.local/bin/sddm-install`: instala el tema, fondo y selección glass.
- `scripts/.local/bin/waybar-build` / `waybar-restart`: Waybar.
- `scripts/.local/bin/dock-restart`: nwg-dock.
- `scripts/.local/bin/theme-toggle`: tema claro/oscuro.
- `scripts/.local/bin/wallpaper-select`: fondo y caché
  `~/.cache/current-wallpaper`.
- `scripts/.local/bin/power-menu`, `keybinds-viewer`, `updates-count`,
  `waybar-settings`, `hypr-test`, `hyprland-glass`.

## Validación

Fuentes:

```bash
fc-match -f '%{family} | %{style} | %{file}\n' "SF Pro Text"
fc-match -f '%{family} | %{style} | %{file}\n' "SF Pro Display"
fc-match -f '%{family} | %{style} | %{file}\n' "JetBrainsMono Nerd Font Mono"
sudo -u sddm fc-match -f '%{family} | %{style} | %{file}\n' "SF Pro Text"
```

GTK/Qt:

```bash
gsettings get org.gnome.desktop.interface font-name
gsettings get org.gnome.desktop.interface document-font-name
gsettings get org.gnome.desktop.interface monospace-font-name
gsettings get org.gnome.desktop.wm.preferences titlebar-font
grep -n 'gtk-font-name' ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini
grep -n -A3 '^\[Fonts\]' ~/.config/qt5ct/qt5ct.conf ~/.config/qt6ct/qt6ct.conf
```

Lockscreen:

```bash
~/.local/bin/lock-screen
```

Comprobar que el icono wifi se ve completo y que el campo de contraseña
funciona. Desbloquear con la contraseña normal.

Waybar, SwayNC y dock:

```bash
~/.local/bin/waybar-restart
swaync-client -rs
~/.local/bin/dock-restart
```

SDDM después de reiniciar:

```bash
grep -n '^font' /usr/share/sddm/themes/glass/theme.conf
grep -n '^import' /usr/share/sddm/themes/glass/Main.qml
journalctl -u sddm -b --no-pager | grep -Ei 'theme|qml|error|warning' | tail -50
```

Se esperan `font=SF Pro Text`, `fontDisplay=SF Pro Display` e imports con
versión (`QtQuick 2.15`, `QtQuick.Controls 2.15`, `QtGraphicalEffects 1.0`).

## Rollback

Revisar el commit de esta fase:

```bash
git show --stat HEAD
git show HEAD -- README.md
```

Backups de `fonts-apply`:

```text
~/.config/gtk-3.0/settings.ini.bak.<fecha>
~/.config/gtk-4.0/settings.ini.bak.<fecha>
~/.config/qt5ct/qt5ct.conf.bak.<fecha>
~/.config/qt6ct/qt6ct.conf.bak.<fecha>
```

Restaurar uno:

```bash
cp -a ~/.config/gtk-3.0/settings.ini.bak.<fecha> ~/.config/gtk-3.0/settings.ini
```

Backups de `sddm-install`:

```text
/etc/sddm.conf.bak.<fecha>
/etc/sddm.conf.d/the_hyde_project.conf.bak.<fecha>
/var/backups/sddm-themes/glass.<fecha>
```

Restaurar configuración y tema:

```bash
sudo cp -a /etc/sddm.conf.bak.<fecha> /etc/sddm.conf
sudo cp -a /etc/sddm.conf.d/the_hyde_project.conf.bak.<fecha> /etc/sddm.conf.d/the_hyde_project.conf
sudo cp -a /var/backups/sddm-themes/glass.<fecha>/. /usr/share/sddm/themes/glass/
```

El tema anterior `sddm-astronaut-theme` sigue instalado. Para volver a él,
cambiar `Current=sddm-astronaut-theme` en `/etc/sddm.conf` con un backup previo.

Las fuentes system-wide de `/usr/local/share/fonts/sf-pro` no se borran
automáticamente; si se decide revertir, eliminarlas manualmente y ejecutar
`sudo fc-cache -f`.
