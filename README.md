# dotfiles

Configuración personal de Arch Linux + Hyprland con estética macOS/Liquid Glass.
Incluye Hyprland, Hyprlock, Hypridle, Waybar, SwayNC, Rofi, nwg-dock-hyprland,
Kitty, tema SDDM propio y un sistema de tema claro/oscuro compartido.

Casi toda la personalización (fondo de escritorio, avatar, fondo y desenfoque del
bloqueo y del login, módulos de la barra) se hace desde un único menú de
**Ajustes**: botón de engranaje de Waybar o `SUPER+,`.

## Arquitectura

La sesión activa usa la configuración del repo, no `~/.config/hypr`:

```text
/usr/local/bin/hyprland-glass
  -> start-hyprland -- -c ~/dotfiles/hypr/.config/hypr/session.lua
```

Archivos y rutas activas:

- `~/dotfiles/hypr/.config/hypr/session.lua`: entrada real de la sesión.
- `~/dotfiles/hypr/.config/hypr/hyprland.lua`: configuración base.
- `~/dotfiles/hypr/.config/hypr/daily.lua`: atajos y servicios de sesión.
- `~/dotfiles/hypr/.config/hypr/test.lua`: sesión de prueba aislada.
- `~/dotfiles/hypr/.config/hypr/legacy/`: `.conf` antiguos archivados; no se cargan.
- `~/dotfiles/hypr/.config/hypr/hypridle.conf`: bloqueo y suspensión (hyprlang).
- `~/dotfiles/hypr/.config/hypr/hyprlock.conf`: lockscreen (hyprlang).
- `~/.config/theme -> ~/dotfiles/theme/.config/theme`: colores y modo.
- `~/.config/theme/appearance.conf`: ajustes de apariencia (fondos y desenfoque);
  ignorado por Git.
- `~/.config/nwg-dock-hyprland -> ~/dotfiles/nwg-dock-hyprland/.config/nwg-dock-hyprland`.
- `~/.local/bin/* -> ~/dotfiles/scripts/.local/bin/*`: scripts.
- Waybar usa `~/.cache/waybar/config.json` generado por `waybar-build` y
  `~/dotfiles/waybar/.config/waybar/style.css`.
- SwayNC se lanza con `-c`/`-s` apuntando al repo.
- Rofi, Kitty y nwg-dock se lanzan con rutas explícitas del repo.

`~/.config/hypr` contiene configuraciones HyDE antiguas y no es la configuración
activa. No editar allí esperando cambios en la sesión.

## Migración a Lua

Hyprland 0.57 ya no lee `.conf`; la sesión usa Lua. La conversión se hace con
`hyprconf2lua >= 1.7.0` (v1.8.1 probada) y el script del repo:

```bash
cd ~/dotfiles
./hypr-lua-migrate.sh --force          # migra e instala el lanzador
./hypr-lua-migrate.sh --force --no-install  # sin tocar /usr/local/bin
```

El script hace copia en `~/.dotfiles-backup/hypr-lua-<fecha>/`, convierte
`hyprland` y `daily`, valida con `luac`, archiva los `.conf` en
`hypr/.config/hypr/legacy/` y deja `hypridle.conf`/`hyprlock.conf` intactos.
Después valida la sesión sin iniciarla:

```bash
Hyprland --verify-config -c ~/dotfiles/hypr/.config/hypr/session.lua
```

Para probar de verdad, usar otro TTY (`Ctrl+Alt+F3`) y ejecutar `hypr-test`;
dentro, `hyprctl configerrors` debe estar vacío.

## Dependencias principales

```text
hyprland hyprlock hypridle waybar swaync nwg-dock-hyprland
rofi kitty sddm qt5-quickcontrols2 qt5-graphicaleffects
imagemagick zenity
jq networkmanager brightnessctl pamixer playerctl grim slurp
wl-clipboard cliphist swaybg
hyprpolkitagent xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
kvantum kvantum-qt5 qt5ct qt6ct
network-manager-applet blueman pacman-contrib libnotify
```

Para migrar la configuración: `hyprconf2lua >= 1.7.0` (vía `pipx` o clon local).

Fuentes:

- `SF Pro Text`, `SF Pro Display`, `SF Pro Rounded` y `SF Pro`.
- `JetBrainsMono Nerd Font` y `JetBrainsMono Nerd Font Mono`.
- `Inter` sigue instalada como respaldo, pero ya no se referencia en las
  configuraciones.

Criterio tipográfico:

- `SF Pro Text` es la fuente general de interfaz.
- `SF Pro Display` se usa en títulos, reloj, fecha grande y nombres.
- `JetBrainsMono Nerd Font Mono` queda solo para terminal, campos
  monoespaciados y glifos Nerd (wifi, batería, iconos).

SF Pro no se versiona en el repo. La copia usada está en:

```text
~/.local/share/fonts/San-Francisco-Pro-Fonts-master/
```

## Instalación de symlinks

Si faltan en un equipo nuevo (también al añadir scripts nuevos):

```bash
ln -sfn ~/dotfiles/theme/.config/theme ~/.config/theme
ln -sfn ~/dotfiles/nwg-dock-hyprland/.config/nwg-dock-hyprland ~/.config/nwg-dock-hyprland
for f in ~/dotfiles/scripts/.local/bin/*; do
  ln -sfn "$f" "$HOME/.local/bin/$(basename "$f")"
done
```

## Ajustes de apariencia

El menú de Ajustes se abre desde el botón de engranaje de Waybar o con `SUPER+,`
(`scripts/.local/bin/settings-menu`). Entradas:

| Entrada | Qué hace |
|---|---|
| Fondo de escritorio | Abre `wallpaper-select` (también `SUPER+SHIFT+W`). |
| Avatar de perfil | Abre `avatar-select` en una terminal (puede pedir `sudo`). |
| Fondo de la pantalla de bloqueo | Igual que el escritorio, una imagen de la carpeta de wallpapers u otra imagen. |
| Fondo del inicio de sesión | Igual, y sincroniza SDDM con `sddm-install` (pide `sudo`). |
| Desenfoque del bloqueo | Activa o desactiva el desenfoque del fondo de hyprlock. |
| Desenfoque del inicio de sesión | Activa o desactiva el desenfoque del fondo de SDDM y sincroniza (pide `sudo`). |
| Módulos de la barra | Abre `waybar-settings`: activar, desactivar y mover módulos. |
| Aplicaciones del dock | Abre `dock-settings`: añade o quita apps fijadas de nwg-dock. |
| Ocultar dock automáticamente | Activa o desactiva `-d` y reinicia nwg-dock. |
| Ocultar barra automáticamente | Activa o desactiva el daemon `bar-autohide` y reinicia Waybar. |

Los ajustes se guardan en `~/.config/theme/appearance.conf` (ignorado por Git) con
`appearance get|set`:

| Clave | Valores | Por defecto |
|---|---|---|
| `lock_bg` | `desktop` o ruta de una imagen | `desktop` |
| `lock_blur` | `on` / `off` | `off` |
| `sddm_bg` | `desktop` o ruta de una imagen | `desktop` |
| `sddm_blur` | `on` / `off` | `on` |
| `dock_autohide` | `on` / `off` | `on` |
| `bar_autohide` | `on` / `off` | `off` |

Con `desktop`, el bloqueo usa siempre el wallpaper actual
(`~/.cache/current-wallpaper`). SDDM usa el wallpaper que había al ejecutar
`sddm-install`, así que se actualiza al sincronizar.

Las imágenes elegidas con «Otra imagen…» se copian a
`~/.config/theme/backgrounds/` (ignorada por Git), para que el ajuste no se rompa
si se borra el original.

Scripts implicados:

- `appearance`: lee y escribe `appearance.conf`.
- `appearance-wall lock|sddm`: imprime la ruta del fondo que corresponde, con
  respaldo a `~/Pictures/wallpapers/wall.jpg`.
- `bar-autohide`: oculta Waybar cuando el cursor baja del borde superior y la
  muestra al volver a `y <= 4`; se controla con `bar_autohide`.
- `dock-settings`: añade o quita clases de `~/.cache/nwg-dock-pinned`.
- `lock-screen`: usa `appearance-wall lock` y aplica `lock_blur`.
- `sddm-install`: usa `appearance-wall sddm` y escribe `blur=` en `theme.conf`.

Desde la terminal:

```bash
~/.local/bin/appearance set lock_blur on
~/.local/bin/appearance get lock_blur off
~/.local/bin/appearance-wall lock
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

El bloqueo se lanza con (`SUPER+L`, el panel de energía o `hypridle`):

```bash
~/.local/bin/lock-screen
```

`lock-screen` genera `~/.cache/hyprlock-run.conf` sustituyendo `@WALL@` por el
fondo elegido (`appearance-wall lock`), `@STATUS@` por el estado de `lock-info` y
`@AVATAR_BLOCK@` por el bloque del avatar, y luego ejecuta `hyprlock` con ese
archivo. No editar el archivo de caché; editar
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
- El fondo es una imagen (`@WALL@`), no una captura del escritorio. Por defecto
  es el wallpaper actual, o el que se haya elegido en Ajustes (`lock_bg`).
- El desenfoque se controla desde Ajustes (`lock_blur`). `lock-screen` borra las
  líneas `blur_passes`/`blur_size` del bloque `background` del archivo generado
  y escribe `blur_passes = 0` (desactivado, valor por defecto) o `blur_passes = 3`
  con `blur_size = 7` (activado). La plantilla no se toca.
- El avatar se genera en `@AVATAR_BLOCK@`: imagen de 80 px si
  `avatar_mode=image`, o círculo con inicial si no hay imagen válida.
  La imagen se toma de `~/.config/theme/avatar.conf`/`avatar.png`.

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
$red = rgba(d70015ff)        # light
```

`lock-info` se versiona con el repo y es requerido por `lock-screen`.

## Avatar de perfil

El avatar se comparte entre el lockscreen y SDDM. Hay dos modos:

- `initials`: círculo con la inicial del nombre del usuario.
- `image`: imagen circular, recortada y normalizada a 512x512.

Avatares base versionados en:

```text
theme/.config/theme/avatars/
  aurora.png
  forest.png
  midnight.png
  sunset.png
```

Selección interactiva (también desde Ajustes, «Avatar de perfil»):

```bash
~/.local/bin/avatar-select
```

El menú ofrece `Iniciales`, los avatares base, los avatares propios de
`avatars/custom/` (con el sufijo `(propio)`) e `Imagen personalizada…`. Cada
entrada se resuelve a su ruta completa, así que un nombre repetido en `avatars/` y
`custom/` no se confunde. La imagen personalizada se elige con Zenity y se recorta
al centro con ImageMagick.

También se puede usar sin menú:

```bash
~/.local/bin/avatar-select initials
~/.local/bin/avatar-select set ~/Pictures/mi-foto.jpg
~/.local/bin/avatar-select --no-sddm set ~/Pictures/mi-foto.jpg
```

La selección se guarda en `~/.config/theme/avatar.conf` y la copia de trabajo
en `~/.config/theme/avatar.png`. Ambos están ignorados por Git:

```text
avatar_mode=image
avatar_image=/home/shadow/.config/theme/avatar.png
```

El lockscreen lee ese archivo al bloquear. Para SDDM, `avatar-select` intenta
sincronizar con `sddm-install` (pide `sudo`); si se usa `--no-sddm`, hay que
ejecutar:

```bash
~/.local/bin/sddm-install dark
```

`sddm-install` copia `avatar.png` al tema, escribe `avatarMode`/`avatar` en
`theme.conf` y conserva el modo `initials` si no hay imagen válida. El avatar
no se versiona; solo se versionan las imágenes base.

Para añadir una imagen propia al menú sin versionarla, guardarla en
`~/.config/theme/avatars/custom/` (ignorada por Git). Los avatares base de
`avatars/` sí se versionan. La copia de trabajo seguirá siendo
`~/.config/theme/avatar.png` (ignorada).

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
- Copia el fondo elegido (`appearance-wall sddm`) como `background.<ext>`.
- Copia el avatar seleccionado como `avatar.png`, si existe.
- Actualiza `background`, `mode`, `avatarMode`, `avatar` y `blur` en
  `theme.conf`. `blur` sale de `sddm_blur` (`on` por defecto).
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

### Claves de `theme.conf`

- `background`: imagen de fondo, copiada junto al tema.
- `mode`: `dark` o `light`; el menú del greeter («?») permite cambiarlo solo para
  esa sesión.
- `font` y `fontDisplay`: `SF Pro Text` y `SF Pro Display`.
- `clock`: `bar` (píldora arriba a la derecha) o `big` (reloj grande).
- `avatarMode` y `avatar`: `initials` o `image`, y la imagen.
- `blur`: `on` u `off`. Si falta, el fondo se desenfoca.

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
  - `hasAvatar` muestra `config.avatar` en un círculo con `OpacityMask` cuando
    `avatarMode=image`; si no, muestra la inicial.
  - Es compatible con Qt5: `import QtQuick 2.15`,
    `import QtQuick.Controls 2.15` e `import QtGraphicalEffects 1.0`.
  - El fondo usa `FastBlur` de QtGraphicalEffects; no usa `QtQuick.Effects`
    ni `MultiEffect`, que son Qt6. Su `radius` es 0 si `config.blur` vale `off`
    y 64 en cualquier otro caso.

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
usuario `sddm` vea SF Pro ni lea el avatar. Para eso está `fonts-install` y la
verificación con `sudo -u sddm`.

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
- `#window`: `SF Pro Text`, peso 500.
- `group/workspaces` agrupa `custom/ws1`…`custom/ws4`: cada workspace muestra
  un único glifo de su ventana activa, o su número si está vacío, con píldora
  de ancho fijo. Los módulos custom solo pueden usar glifos Nerd Font, no
  iconos GTK; el mapa de clases está en
  `scripts/.local/bin/workspace-pill`. Click enfoca el workspace y, si ya está
  activo, cicla sus ventanas. `waybar-restart` inicia `workspace-pill daemon`,
  que actualiza los cuatro módulos con `SIGRTMIN+8`; se mantiene
  `hyprland/window` para el título.
- Los iconos Nerd usan el fallback Mono.
- El resto de módulos heredan la fuente global.
- `bar-autohide` oculta la barra con `SIGUSR1` cuando el cursor baja de
  `y = 48` y la muestra al acercarse al borde superior. Se activa en Ajustes o
  con `appearance set bar_autohide on` + `waybar-restart`.

La configuración se genera con:

```bash
~/.local/bin/waybar-build
~/.local/bin/waybar-restart
```

`waybar-build` combina `modules.json` y `definitions.json` en
`~/.cache/waybar/config.json`. `modules.json` desactiva `temperature`,
`bluetooth` y `network`.

El botón de engranaje (`custom/settings`) abre `settings-menu`. El módulo
`custom/wallpaper` ya no está en la barra: el cambio de fondo está en Ajustes y
en `SUPER+SHIFT+W`. La entrada «Módulos de la barra» de Ajustes abre
`waybar-settings`, que activa, desactiva y mueve módulos entre zonas.

## SwayNC

Archivo: `swaync/.config/swaync/style.css`.

- Fuente global: `"SF Pro Text", "JetBrainsMono Nerd Font Mono"`.
- `.widget-title`: `SF Pro Text`.
- `.summary`: mantiene `font-weight: 600`.
- Los glifos Nerd caen en la Mono.

Recargar:

```bash
swaync-client -rs
```

## Rofi

Archivos: `rofi/.config/rofi/config.rasi` y `power.rasi`.

- Lanzador: `font: "SF Pro Text 13"`.
- Menú de energía: `font: "SF Pro Text 13"`; cada opción muestra un icono de
  44 px y una etiqueta `SF Pro Text 10` debajo, dentro de un botón circular
  (`border-radius: 52px`) en una fila de 6 columnas.
- `power-menu` usa `SF Pro Text 13` para el mensaje de confirmación; la opción
  `Cancelar` usa el tamaño compacto de 10 px definido en `power.rasi`.
- El menú de energía activa `hover-select`, `me-select-entry: ""` y
  `me-accept-entry: "MousePrimary"` en `power.rasi`. Así, al pasar el cursor la
  opción queda seleccionada y un solo clic la activa, tanto en el menú principal
  como en la confirmación.
- El `icon-theme` sigue fijado a `WhiteSur-dark`; no se cambió en esta fase.
  Es una inconsistencia conocida con `theme-toggle`, que usa
  `WhiteSur-glass`/`WhiteSur-glass-light`.
- `settings-menu`, `avatar-select`, `wallpaper-select`, `dock-settings` y
  `waybar-settings` reutilizan `config.rasi`.
- En `power.rasi`, el elemento seleccionado solo cambia de color y borde de
  acento; el tamaño se mantiene para evitar saltos de layout. Rofi no soporta
  transiciones ni escalado de iconos; el aumento real solo se aplica a los
  iconos del dock.

Probar:

```bash
rofi -show drun -config ~/dotfiles/rofi/.config/rofi/config.rasi
~/.local/bin/power-menu
rofi -dump-theme -config ~/dotfiles/rofi/.config/rofi/power.rasi >/dev/null
```

## nwg-dock, Kitty y Hyprland

- nwg-dock declara `SF Pro Text` con fallback Nerd Font en su CSS; no depende
  de `gtk-font-name`.
- Las apps fijadas se guardan como clases, una por línea, en
  `~/.cache/nwg-dock-pinned` (`kitty`, `firefox`, …). «Aplicaciones del dock»
  en Ajustes abre `dock-settings` para añadirlas o quitarlas.
- `dock_autohide` controla el flag `-d`; `dock-restart` lo lee de
  `appearance.conf`. El valor por defecto es `on`.
- Al pasar el cursor, los iconos del dock se amplían con
  `-gtk-icon-transform: scale(1.18)` y una transición de 180 ms.
- Kitty sigue con `JetBrainsMono Nerd Font` tamaño 11. Es una monoespaciada
  deliberada; no se usa SF Pro en la terminal.
- Hyprland no dibuja títulos de ventana. Los títulos visibles los pinta Waybar
  con `SF Pro Text`; las apps GTK/Qt usan `fonts-apply`.
- Las ventanas usan `windowsIn = popin 92%` y `windowsOut = gnomed` (efecto
  lámpara mágica) con la curva `ease`.

Recargar el dock:

```bash
~/.local/bin/dock-restart
```

## Tema claro/oscuro

`theme-toggle` cambia los symlinks `current.conf`, `current.lua`, `current.css`,
`current.rasi` y `current.kitty`, además de GTK, iconos, Kvantum, Waybar,
SwayNC, Kitty y nwg-dock:

```bash
~/.local/bin/theme-toggle        # alterna
~/.local/bin/theme-toggle dark
~/.local/bin/theme-toggle light
```

El lockscreen sigue el modo porque lee `~/.config/theme/current.conf`.
Hyprland lee los colores desde `~/.config/theme/current.lua`.
SDDM es independiente: su modo se define en `sddm/glass/theme.conf` y se puede
cambiar con `sddm-install dark|light` o desde el menú del greeter (solo para esa
sesión).

Pendientes conocidos de integración visual, no tocados en esta fase:

- Rofi fija `WhiteSur-dark` y no sigue el modo claro/oscuro.
- Qt5ct/Qt6ct usan `Tela-circle-dracula` como icon theme.
- `theme-toggle` no actualiza el tema/iconos de GTK4, solo `fonts-apply` toca su
  fuente.
- La configuración de Hyprland ya está en Lua; los `.conf` quedan archivados en
  `hypr/.config/hypr/legacy/` y no se cargan.

## Scripts

- `scripts/.local/bin/settings-menu`: menú de Ajustes (engranaje de Waybar o
  `SUPER+,`).
- `scripts/.local/bin/appearance`: lee y escribe `~/.config/theme/appearance.conf`.
- `scripts/.local/bin/appearance-wall`: resuelve el fondo de bloqueo o de SDDM.
- `scripts/.local/bin/lock-screen`: genera el config de hyprlock y bloquea.
- `scripts/.local/bin/lock-info`: fecha, nombre, inicial y estado.
- `scripts/.local/bin/avatar-select`: elige iniciales, avatar base, avatar propio
  o imagen personalizada y sincroniza SDDM.
- `scripts/.local/bin/fonts-apply`: fuentes de usuario (GTK/Qt/gsettings).
- `scripts/.local/bin/fonts-install`: SF Pro system-wide para SDDM.
- `scripts/.local/bin/sddm-install`: instala el tema, fondo, avatar y desenfoque
  de glass.
- `scripts/.local/bin/waybar-build` / `waybar-restart`: Waybar.
- `scripts/.local/bin/bar-autohide`: auto-ocultado de Waybar por posición del cursor.
- `scripts/.local/bin/dock-restart`: nwg-dock.
- `scripts/.local/bin/dock-settings`: aplicaciones fijadas del dock.
- `theme/.local/bin/theme-toggle`: tema claro/oscuro.
- `scripts/.local/bin/theme-lua-gen`: regenera `colors.lua` desde `colors.conf`.
- `scripts/.local/bin/wallpaper-select`: fondo y caché
  `~/.cache/current-wallpaper`.
- `scripts/.local/bin/power-menu`, `keybinds-viewer`, `updates-count`,
  `waybar-settings`, `hypr-test`, `hyprland-glass`.
- `hypr-lua-migrate.sh` (raíz del repo): migra Hyprland a Lua, valida, archiva
  los `.conf` y actualiza el lanzador.

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

Ajustes de apariencia y desenfoque del bloqueo:

```bash
~/.local/bin/appearance set lock_blur on
~/.local/bin/lock-screen            # fondo desenfocado
~/.local/bin/appearance set lock_blur off
cat ~/.config/theme/appearance.conf
~/.local/bin/appearance-wall lock
```

Avatar:

```bash
~/.local/bin/avatar-select --no-sddm initials
~/.local/bin/avatar-select --no-sddm set ~/dotfiles/theme/.config/theme/avatars/aurora.png
cat ~/.config/theme/avatar.conf
~/.local/bin/lock-screen
```

Después, sincronizar SDDM con `~/.local/bin/sddm-install dark` y comprobar:

```bash
grep -n '^avatar\|^blur\|^background' /usr/share/sddm/themes/glass/theme.conf
sudo -u sddm test -r /usr/share/sddm/themes/glass/avatar.png && echo "sddm puede leer el avatar"
```

Waybar, SwayNC y dock:

```bash
~/.local/bin/waybar-restart
swaync-client -rs
~/.local/bin/dock-restart
```

SDDM después de reiniciar:

```bash
grep -n '^font\|^avatar\|^blur' /usr/share/sddm/themes/glass/theme.conf
grep -n '^import' /usr/share/sddm/themes/glass/Main.qml
journalctl -u sddm -b --no-pager | grep -Ei 'theme|qml|error|warning' | tail -50
```

Se esperan `font=SF Pro Text`, `fontDisplay=SF Pro Display`, `blur=on` u `off` e
imports con versión (`QtQuick 2.15`, `QtQuick.Controls 2.15`,
`QtGraphicalEffects 1.0`).

Hyprland en Lua:

```bash
Hyprland --verify-config -c ~/dotfiles/hypr/.config/hypr/session.lua
for f in ~/dotfiles/hypr/.config/hypr/*.lua; do luac -p "$f"; done
hyprctl configerrors
```

En un TTY aparte, `hypr-test` debe abrir la sesión de prueba y `hyprctl
configerrors` debe quedar vacío.

Antes de commitear:

```bash
for f in hypr-lua-migrate.sh scripts/.local/bin/* theme/.local/bin/*; do
  grep -q '^#!.*bash' "$f" && { bash -n "$f" || echo "FALLO: $f"; }
done
git diff --check
git status --short
git check-ignore -v theme/.config/theme/appearance.conf theme/.config/theme/avatar.conf \
  theme/.config/theme/avatar.png theme/.config/theme/backgrounds/x.jpg \
  theme/.config/theme/avatars/custom/x.png
```

## Rollback

Revisar el commit de esta fase:

```bash
git show --stat HEAD
git show HEAD -- README.md
```

Backup de la migración Lua:

```text
~/.dotfiles-backup/hypr-lua-<fecha>/
```

Restaurar la configuración anterior:

```bash
cp -a ~/.dotfiles-backup/hypr-lua-<fecha>/hypr/. ~/dotfiles/hypr/.config/hypr/
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

Para deshacer los ajustes de apariencia, borrar `~/.config/theme/appearance.conf`:
el bloqueo vuelve al wallpaper actual sin desenfoque y SDDM al wallpaper actual con
desenfoque tras ejecutar `sddm-install`.
