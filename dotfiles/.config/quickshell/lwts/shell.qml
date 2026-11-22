// LWTS - Lightweight Wayland Tiling Shell (niri + Quickshell). Map of the tree: README.md.
// Entry point: only wires modules together, no logic here.
// (L.W.T.S. - loving when the shell stays light.)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services
import qs.bar
import qs.overlays
import qs.launcher
import qs.popups
import qs.desktop

ShellRoot {
  Component.onCompleted: { NiriConf.apply(); PadCal.start(); Reminders.start(); Modules.ctx = { bar: bar, popups: popups, launcher: launcher } }   // modules (services/Modules.qml) get the shell's objects   // Modules: read <shell>/modules at start   // write ~/.config/niri/lwts.kdl from settings.toml at start (niri includes it)
  settings.watchFiles: false   // reload by hand
  Bar {
    id: bar
    Launcher { id: launcher; home: bar; floater: floatHost }   // drops live inside the bar window
    Popups { id: popups; bar: bar }
    Toasts { bar: bar; avoidL: launcher.visible && !launcher.bar.floating ? launcher.edgeL : -1 }
    // one drop at a time: a bar click / hotkey closes the launcher, the launcher closes a pop-up
    onPanel: (name, x) => { if (name === "time") { popups.close(); launcher.toggleTime(x - bar.margins.left); return }   // the combined time shade is a mode of the launcher drop
                           launcher.close(true); popups.toggle(name, x - bar.margins.left) }
    onQuick: launcher.toggle()
    onLaunch: launcher.toggle(true)   // right click on the bar: the drop; hotkey / ipc: a plate under the cursor
    onMenu: (handle, x) => { launcher.close(true); popups.openMenu(handle, x - bar.margins.left) }
  }
  Connections { target: launcher; function onVisibleChanged() { if (launcher.visible) { popups.close(); if (launcher.bar === bar) bar.grab = true } } }   // bar.grab is shared: closing the pop-up must not take the keyboard from the launcher
  Connections { target: launcher; function onDetails(p) { popups.toggle(p, -1) } }

  IpcHandler {   // re-read the QML in place: unlike pkill + start, the process (and whatever it launched) survives
    target: "shell"
    function reload(): void { Quickshell.reload(false) }
  }
  IpcHandler {
    target: "panels"
    function toggle(name: string): void { if (name === "time") { popups.close(); launcher.toggleTime(bar.xFor(name)); return } launcher.close(true); popups.toggle(name, bar.xFor(name)) }   // audio | net | bt | sysmon | clock | notif | media
  }
  IpcHandler {
    target: "speedtest"
    function run(): void { NetInfo.speedTest() }   // the same as the TEST button of the Network tab
    function status(): string { return NetInfo.testing ? "running " + NetInfo.phase : JSON.stringify(NetInfo.speed) }
  }
  IpcHandler {
    target: "notifications"
    function toggle(): void { launcher.close(true); popups.toggle("notif", bar.xFor("notif")) }   // Super+N
    function dismiss(): void { if (Notifs.popups.length) Notifs.hide(Notifs.popups[0]) }   // Super+Escape (settings_spec 7.2)
    function dnd(): void { Notifs.toggleDnd() }   // Do not disturb on/off (same as the Quick-settings tile)
    function dndState(): string { return Notifs.dnd ? "on (" + Notifs.mode + ")" : "off" }
  }
  FloatHost { id: floatHost }   // the launcher on a monitor without the bar
  Osd { bar: bar }
  ScreenshotArea {}   // Mod+Shift+S: drag, capture on release (overlays/ScreenshotArea.qml)
  WindowSwitcher {}   // Alt+Tab (overlays/WindowSwitcher.qml)
  // --- what the compositor does not give us on niri (all of it lives here, nothing external): see MIGRATION notes
  WallpaperLayer {}   // the wallpaper (still / video), one background surface per monitor
  DeskHost {}         // desktop widgets (services/Desk.qml, desktop/): one Bottom surface per output that has widgets
  LockScreen {}       // ext-session-lock + PAM; Lock.lock() from the power menu, idle, `qs ipc call lock lock`
  LockFade {}         // fades a veil out over the windows after a password unlock
  LockPreview {}      // window with the lock look for tuning: `qs -c lwts ipc call lockpreview toggle`
  CastPicker {}       // screen-share picker: overlays/CastPicker.qml, fed by ~/.local/bin/lwts-portal over a socket
  PolkitDialog {}     // polkit agent: the password dialog for pkexec and GUI apps
  // DialogHost {}    // Yes/No dialogs for scripts (overlays/DialogHost.qml + services/Prompt.qml): unfinished, the singleton is not created inside this shell; only Game Mode needed it
  TasksWindow {}      // Tasks: performance + processes (overlays/TasksWindow.qml, `qs -c lwts ipc call tasks toggle`)
  IpcHandler {
    target: "tasks"
    function toggle(): void { Tasks.toggle() }
    function res(id: string): void { Tasks.res = id }
    function open(tab: string): void { Tasks.tab = ["proc", "perf", "start", "det", "svc"].includes(tab) ? tab : "proc"; Tasks.shown = true }   // tab: proc | perf | start | det | svc
  }
  IdleManager {}      // lock / screen off / sleep timers
  LockTriggers {}     // lock at session start (autologin) and before every suspend, however it was started
  Binding { target: Wallpaper; property: "paused"; value: Session.game || Lock.locked }   // a video wallpaper stops when nobody sees it
  DisplayConfirm {}   // Keep / Revert after Settings -> Displays (the engine reverts by itself in 12 s)
  IpcHandler {
    target: "osd"
    function caps(): void { OsdState.checkCaps() }               // optional: OSD reads the LED itself
    function brightness(): void { OsdState.checkBrightness() }   // brightness.sh
  }
  IpcHandler {   // XF86MonBrightnessUp/Down in niri: `qs -c lwts ipc call brightness up`
    target: "brightness"
    function up(): void { Brightness.step(0.05) }
    function down(): void { Brightness.step(-0.05) }
    function set(percent: int): void { Brightness.set(percent / 100) }
    function get(): int { return Math.round(Brightness.value * 100) }
  }

  IpcHandler {
    target: "sounds"
    function play(event: string): void { Sounds.play(event) }   // event id, e.g. screen-capture (from binds)
  }

  IpcHandler {
    target: "launcher"
    function toggle(): void { launcher.toggle() }   // Super+Space
    function close(): void { launcher.close() }
    function search(text: string): void { launcher.search(text) }
    function settings(section: int): void { launcher.openSettings(section) }   // 0 Look … 4 Other
    function settingsId(id: string): void { launcher.openSettingsId(id) }
    function tab(section: int, group: int): void { launcher.openSettings(section); launcher.settingsPage.group = group; launcher.settingsPage.pane = "page"; launcher.settingsPage.row = launcher.settingsPage.firstRow() }   // tests: any settings tab
    function tabId(section: string, group: int): void { launcher.openSettingsId(section); launcher.settingsPage.group = group; launcher.settingsPage.pane = "page"; launcher.settingsPage.row = launcher.settingsPage.firstRow() }
    function pick(kind: string): void { launcher.openSettings(0); launcher.openPicker(kind) }   // wallpaper | palette
  }

  IpcHandler {   // Lite (game mode): a bind or script can flip it
    target: "lite"
    function toggle(): void { Session.toggleGame() }
    function status(): string { return Session.game ? "on" : "off" }
    function wrapPid(pid: int): void { Session.wrapPid(pid) }   // lwts-game: the game's pid; the shell watches it and turns Lite off when it is gone
    function wrapStart(): void { Session.wrapStart() }   // old wrapper, ignored
    function wrapStop(): void { Session.wrapStop() }
  }

  IpcHandler {   // desktop widgets: `qs -c lwts ipc call desk add clockweather DP-2 0 0`
    target: "desk"
    function add(wid: string, mon: string, x: int, y: int): void { Desk.add(wid, mon, x, y) }
    function addWith(wid: string, mon: string, x: int, y: int, opts: string): void { const o = {}; opts.split(";").forEach(kv => { const i = kv.indexOf("="); if (i > 0) o[kv.slice(0, i)] = kv.slice(i + 1) }); Desk.add(wid, mon, x, y, o) }   // opts "folder=/path;when=work"
    function iconMenu(mon: string, x: int, y: int, path: string): void { Desk.selection = [path]; Desk.testMenu(mon, x, y, true) }   // test: the icon menu for a path
    function paste(): void { Desk.paste() }   // same as the menu row (test / bind)
    function terminal(): void { Desk.openTerminal() }
    function work(on: bool): void { Prefs.set("desk_work", on) }
    function remove(id: string): void { Desk.remove(id) }
    function move(id: string, x: int, y: int): void { Desk.move(id, x, y) }
    function menu(mon: string, x: int, y: int): void { Desk.testMenu(mon, x, y, false) }   // test: open the desktop menu without a click
    function list(): string { return Desk.placed.map(Desk.enc).join("\n") + (Desk.awake ? "\n[awake]" : "\n[asleep]") }
  }

  IpcHandler {
    target: "bar"
    // game-mode.lua: opaque = solid layers, no motion / OSD; edges = bar flush with the screen edges
    function gameMode(playing: bool, opaque: bool, edges: bool): void { Theme.playing = playing; Theme.game = opaque; Theme.lite = edges }
  }
}
