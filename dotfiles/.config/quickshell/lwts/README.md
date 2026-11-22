# LWTS shell

Quickshell configuration of LWTS (Lightweight Wayland Tiling Shell) for the Niri compositor.

## Run
- Start: `qs -c lwts` (Niri starts it). Log: `qs -c lwts log`. List IPC: `qs -c lwts ipc show`.
- Re-read the QML without restarting: `qs -c lwts ipc call shell reload`.
- IPC targets: `shell`, `bar`, `panels`, `launcher`, `notifications`, `osd`, `sounds`, `shot`, `switcher`, `lite`, `lock`, `lockpreview`, `wallpaper`, `pointer`, `dialog`, plus `ai`, `clip`, `notes` from modules.

## Layout
```
shell.qml     entry point: wires the parts together, no logic
core/         singletons without UI: Prefs (settings), Theme (colours, fonts, geometry), Motion (animation)
services/     talk to the system: audio, network, Bluetooth, power, notifications, wallpaper, lock, niri config, modules, ...
widgets/      building blocks: Tile, Slider, ListRow, Droplet, Icon, NotifCard, OsdContent, ClickAway
bar/          the bar
popups/       panels that open under the bar icons (audio, Bluetooth, network, calendar, media, system monitor, tray, notifications)
launcher/     launcher, Quick settings, picker
settings/     the Settings app
overlays/     lock screen, OSD, polkit and confirmation dialogs, wallpaper layer
modules/      installed optional modules
scripts/      only what cannot be done in QML (shell/Lua helpers, `lwts-module`)
```

## Rules
- Components show state; services talk to the system. A function has one owner: link to it, do not copy.
- Colours only from `Theme.*`; rounding only `Theme.radius` / `radiusCard` / `radiusInner`; borders `Theme.line`; no shadows.
- All animation goes through `Motion.*`. `Motion.off` and game mode (`Theme.game`) must give instant, effect-free behaviour.
- Settings are read and written through `Prefs.get(key, default)` / `Prefs.set(key, value)`; all bindings update by themselves. The file is `~/.config/themes/settings.toml`; every key needs a default in code.
- Reuse `widgets/` before writing a new control. Icons through the `Icon` widget (Phosphor font, `widgets/phosphor.js` maps names to codes).
- Heavy parts that are not always on screen are loaded on demand (`Loader` / `LazyLoader`).
- Back up a file before editing it; reload and look at the result.

## Modules
- A module is a folder `modules/<id>/` with `manifest.json`: `id`, `name`, `version`, `contract` (1) and optional file names: `service`, `settings`, `tiles`, `palettes`, `videowall`.
- Extension points (`services/Modules.qml`): background code (`service`), rows or a whole category in Settings (`settings`; a category is declared with `sectionDef { id, icon, label, before }`), Quick settings tiles (`tiles`), theme palettes (`palettes`), a live wallpaper file (`videowall`). `Modules.openSection` is the id of the Settings category on screen, so a module can load data only while it is open.
- The base never imports a module; a module may import `qs.core` and `qs.services`.
- Manage with `lwts-module list | install [-y] <name|dir> | remove <id>`. Install shows the contents and asks; remove moves the folder to `modules/.removed`. Sources are listed in `~/.config/lwts/sources.toml` (`name = "/path/to/folder/of/modules"`). Modules are read at start: reload after a change.

## QML pitfalls
- `Item` has final properties `top` and `bottom` (anchors): do not use these names for your own properties.
- Inside `ShapePath` there is no `parent`: refer to the `Shape` by `id`.
- Singletons are created on first use and files are read asynchronously: values may appear slightly later, bindings handle that.
- Restarting the shell from a shell command with `pkill -f 'qs -c lwts'` also kills the shell running the command: use `qs -c lwts ipc call shell reload`, or `kill $(pgrep -f '^qs -c lwts')`.
