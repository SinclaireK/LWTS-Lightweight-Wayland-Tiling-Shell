// Settings inside the launcher drop (Tab / click on the mode icon): categories on the left, the page on the right with
// its groups as cards (macOS / GNOME). Closes only by Esc / × / the gear - not by a click outside (LWTS_SPEC 8).
// The launcher input filters rows across all sections. Every row is a choice of ready variants.
// Row types: choice (segments), cycle (‹ value ›), multi (chips on/off), picker (opens the preview strip),
// hotkey (Enter = record new keys, Delete = remove, Backspace = default), action (button), info, header,
// slider (KnoblessSlider: ← → step and apply at once). A row with `pin` gets the 📌 toggle: click or P (settings_spec 1.1).
// Keyboard (forwarded by Launcher.qml): sidebar ↑ ↓, → / Enter into the page; page ↑ ↓ rows, ← → change / move
// between values / chips (nothing changes by passing), Enter = apply / toggle chip / open; Esc = back to the sidebar.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.core
import qs.services
import qs.widgets
import "components"

Item {
  id: st
  // the mouse really moved (Qt also re-sends a still pointer when the content under it changes): key focus hides until the next key
  HoverHandler {
    property point last: Qt.point(-1, -1)
    onPointChanged: {
      const p = point.scenePosition;
      if (Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 3) { if (last.x >= 0 && st.keyNav) st.keyNav = false; last = p }
    }
  }
  property string filter: ""
  signal pick(string kind)   // a picker row asks the launcher for the preview strip
  signal refocus()           // an input row is done: the keys go back to the launcher input
  implicitHeight: 400
  // the launcher sizes the drop to this (capped at its max, longer pages scroll): no empty space under short pages
  readonly property int wantedHeight: filter !== "" ? (rows.length ? card.height + 4 : 36) : Math.max(sideCol.implicitHeight + 10, card.height + 4)

  // ---- row helpers ------------------------------------------------------------------------
  function choice(label, desc, options, get, set) {   // up to 3 options: segments; more: one ‹ value › row (a wall of chips was noise)
    return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function cycle(label, desc, options, get, set) { return { type: "cycle", label, desc, options, get, set } }
  function multi(label, desc, options, isOn, toggle) { return { type: "multi", label, desc, options, isOn, toggle } }
  function slider(label, desc, steps, unit, get, set) { return { type: "slider", label, desc, steps, unit, get, set } }   // settings_spec 1.3
  readonly property var opacitySteps: Array.from({ length: 11 }, (_, i) => Math.round((0.5 + i * 0.05) * 100) / 100)
  function timeOptions() {   // every 30 min, "HH:MM" (settings_spec 2.5 own-time fields)
    const o = []; for (let m = 0; m < 24 * 60; m += 30) { const h = String(Math.floor(m / 60)).padStart(2, "0"), mm = String(m % 60).padStart(2, "0"); o.push([h + ":" + mm, h + ":" + mm]) }
    return o;
  }
  function input(label, desc, get, set, o) { return Object.assign({ type: "input", label, desc, get, set }, o || {}) }   // o: { secret, placeholder, validate(text) -> error or "" }
  function header(label) { return { type: "header", label } }   // a card inside a page
  function tab(label, page) { return page ? { type: "tab", label, page } : { type: "tab", label } }   // page = rows per page for a long list (paged dots, no scroll); a subpage = one settings_spec subsection (tab strip under the title)
  function info(label, value) { return { type: "info", label, value } }
  function px(list) { return list.map(v => [v, String(v)]) }
  function withCur(list, cur) { const c = Number(cur); return list.indexOf(c) >= 0 ? list : list.concat([c]).sort((a, b) => a - b) }
  readonly property var idleSteps: [0, 1, 2, 5, 10, 15, 30, 60]
  readonly property var sleepSteps: [0, 5, 10, 15, 30, 60, 120]
  function batRows() {   // battery: state line + the charge limit (sysfs, root through lwts-priv) when the firmware has it
    const b = Session.bat;
    if (!b || !b.isLaptopBattery) return [];
    const st = b.state === UPowerDeviceState.Charging ? "Charging" : b.state === UPowerDeviceState.Discharging ? "On battery" : b.state === UPowerDeviceState.FullyCharged ? "Full" : "Plugged in";
    const sec = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.state === UPowerDeviceState.Discharging ? b.timeToEmpty : 0;
    const left = sec > 0 ? "  ·  " + Math.floor(sec / 3600) + " h " + Math.round(sec % 3600 / 60) + " min" : "";
    return [header("Battery"), info("Charge", Math.round(b.percentage * 100) + " %  ·  " + st + left)].concat(
      chargeLimit >= 0 ? [cycle("Charge limit", "Stops charging at this level; 100 = off", [[100, "100 %"], [90, "90 %"], [80, "80 %"], [70, "70 %"], [60, "60 %"]].concat(chargeLimit < 100 && [90, 80, 70, 60].indexOf(chargeLimit) < 0 ? [[chargeLimit, chargeLimit + " %"]] : []),
                () => chargeLimit, v => { st.chargeLimit = v; chargeReq.setText(String(v)) })] : []) }   // same path as the Power panel: lwts-powerd (root) applies it and writes the TLP drop-in
  readonly property var logindOpts: [["suspend", "Sleep"], ["lock", "Lock"], ["ignore", "Nothing"], ["poweroff", "Power off"], ["hibernate", "Hibernate"]]
  property var logindCfg: ({})   // /etc/systemd/logind.conf.d/50-lwts.conf (readable by the user), written through lwts-priv
  function logindGet(k, d) { return logindCfg[k] || d }
  function logindSet(arg, k, v) { logindCfg = Object.assign({}, logindCfg, { [k]: v }); Quickshell.execDetached(["pkexec", "/usr/local/libexec/lwts-priv", "logind", arg, v]) }
  FileView { path: "/etc/systemd/logind.conf.d/50-lwts.conf"; watchChanges: true; printErrors: false; onFileChanged: reload()
             onLoaded: { const o = {}; for (const l of text().split("\n")) { const m = l.match(/^(\w+)=(\w+)$/); if (m) o[m[1]] = m[2] } st.logindCfg = o } }
  property bool hasAmdGpu: false   // GPU sensors / clocks are AMD-only (the desktop); Intel-only laptops get no GPU tab
  FileView { path: "/sys/class/drm/card0/device/vendor"; printErrors: false; onLoaded: if (text().trim() === "0x1002") st.hasAmdGpu = true }
  FileView { path: "/sys/class/drm/card1/device/vendor"; printErrors: false; onLoaded: if (text().trim() === "0x1002") st.hasAmdGpu = true }
  property int chargeLimit: 100
  readonly property bool hasChargeCtl: Session.bat && Session.bat.isLaptopBattery
  // the stop level is read from the TLP drop-in lwts-powerd writes: on some ThinkPads the sysfs start / end files read back swapped
  FileView { id: chargeConf; path: "/etc/tlp.d/20-lwts-charge.conf"; printErrors: false; watchChanges: true; onFileChanged: reload()
             onLoaded: { const m = text().match(/STOP_CHARGE_THRESH_BAT0=(\d+)/); st.chargeLimit = m ? parseInt(m[1]) : 100 } }
  FileView { id: chargeReq; path: Quickshell.env("XDG_RUNTIME_DIR") + "/lwts-charge-limit"; printErrors: false }
  function minutes(list) { return list.map(v => [v, v === 0 ? "Never" : v < 60 ? v + " min" : (v / 60) + " h"]) }
  function lockSet(key, v) { Prefs.set(key, v) }   // lock_* keys: overlays/LockContent.qml reads them live
  function manageApp(id, mode) {   // scripts/app-manage.sh in a terminal: pacman / flatpak ask for confirmation themselves
    Quickshell.execDetached(["alacritty", "-e", "bash", Quickshell.env("HOME") + "/.config/quickshell/lwts/scripts/app-manage.sh", id, mode]);
  }
  function toggleIn(key, id, fallback) {   // add / remove an id in a list key of settings.toml
    const l = (Prefs.get(key, fallback) || []).slice(), i = l.indexOf(id);
    if (i >= 0) l.splice(i, 1); else l.push(id);
    Prefs.set(key, l);
  }
  readonly property bool laptop: !!UPower.displayDevice && UPower.displayDevice.isLaptopBattery

  // ---- hotkeys: the `binds { }` block of ~/.config/niri/config.kdl; re-recording rewrites the key text of that line (validated, rolled back on error) ----
  property var binds: []
  property var defaultKeys: ({})   // what a bind does -> its factory keys (~/.config/niri/binds-default.kdl); an action bound twice is left out
  function parseBinds(t) {
    // a removed bind is its own line behind the marker `//off` (written by rebindScript): listed so it can be restored
    return t.split("\n").map(l => { const m = l.replace(/^\/\/off/, "").match(/^\s+((?:Mod|Ctrl|Alt|Shift|Super|XF86|Print|Escape|Home|End|[A-Z0-9_])[\w+]*)\b[^{]*\{\s*(.*?);?\s*\}\s*$/);
                                   return m && { keys: m[1], what: m[2], removed: l.startsWith("//off") } })
            .filter(m => m)
            .filter(b => !b.keys.startsWith("XF86") && !b.keys.includes("mouse:"))
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/niri/config.kdl"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: st.binds = st.parseBinds(text())
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/niri/binds-default.kdl"
    printErrors: false
    onLoaded: { const m = {}, dup = {}; for (const b of st.parseBinds(text())) { if (b.what in m) dup[b.what] = true; m[b.what] = b.keys } for (const w in dup) delete m[w]; st.defaultKeys = m }
  }
  readonly property var rebinds: {
    const m = {};
    for (const r of Prefs.get("rebinds", [])) { const i = r.indexOf("="); if (i > 0) m[r.slice(0, i)] = r.slice(i + 1) }
    return m;
  }
  function restoreBind(keys) {   // a removed bind comes back under its own keys
    rebindProc.command = ["sh", "-c", rebindScript, "sh", Quickshell.env("HOME") + "/.config/niri/config.kdl", keys, keys];
    rebindProc.running = true;
  }
  function setRebind(keys, to) {   // to: new keys, "" = removed (the line is kept behind //off), null = default (not kept: the file is the only source)
    if (to === null || to === keys) return;
    rebindProc.command = ["sh", "-c", rebindScript, "sh", Quickshell.env("HOME") + "/.config/niri/config.kdl", keys, to];
    rebindProc.running = true;
  }
  // $1 file, $2 old keys, $3 new keys ("" = comment the line out): the edited copy must pass `niri validate` (duplicates fail) before it replaces the file
  readonly property string rebindScript: 'f=$1; b=$HOME/.local/state/lwts/backups/niri; mkdir -p "$b"; cp "$f" "$b/config.kdl.before-rebind"; '
    + 'awk -v old="$2" -v new="$3" \'!d && ($1 == old || ($1 == "//off" && $2 == old)) { d = 1; sub(/^[/][/]off/, ""); if (new == "") { print "//off" $0; next } i = index($0, old); $0 = substr($0, 1, i - 1) new substr($0, i + length(old)) } { print }\' "$f" > "$f.tmp" '
    + '&& ! cmp -s "$f" "$f.tmp" && niri validate -c "$f.tmp" >/dev/null 2>&1 && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; exit 1; }'
  Process {
    id: rebindProc
    onExited: code => { if (code !== 0) Quickshell.execDetached(["notify-send", "-t", "3500", "Hotkeys", "Not changed: these keys are already in use, or the config became invalid"]) }
  }
  // ---- mouse DPI: a supported mouse (lwts-mousedpi: Hator Stellar PRO 04d9:a09f) gets the DPI written into it, then the pointer speed
  // is compensated (NiriConf, reference 800); other mice: manual mode, only the compensation. Runs on change only, never in the input path ----
  Process { id: mouseDpiDetect; running: true; command: ["lwts-mousedpi", "detect"]; property bool found: false; onExited: code => found = code === 0 }
  Process {
    id: mouseDpiSet
    property int want: 0
    onExited: code => {
      if (code === 0) Look.setInput({ mouse_dpi: want });
      else Quickshell.execDetached(["notify-send", "-t", "3500", "Mouse DPI", "Not changed: the mouse did not accept the command"]);
    }
  }
  function setMouseDpi(v) {
    if (!mouseDpiDetect.found) { Look.setInput({ mouse_dpi: v }); return }
    if (mouseDpiSet.running) return;
    mouseDpiSet.want = v; mouseDpiSet.command = ["lwts-mousedpi", "set", String(v)]; mouseDpiSet.running = true;
  }
  ShortcutInhibitor { window: QsWindow.window; enabled: st.capturing !== "" }   // niri must not swallow Super+… while keys are being recorded
  function nice(what, keys) {   // a readable name for what a bind does (keys: "SUPER + 3" -> the workspace number)
    const d = (what.match(/direction = "(\w+)"/) || [])[1], n = (keys || "").split(/ \+ |\+/).pop();
    const cap = t => t ? t[0].toUpperCase() + t.slice(1) : "";
    const t = [[/mouse:272|window\.drag/, "Move window (mouse)"], [/window\.resize/, "Resize window (mouse)"],
               [/window\.kill/, "Kill window"], [/function\($/, "Close window"],
               [/fullscreen\(\{ mode = 1/, "Maximize"], [/fullscreen\(\{ mode = 0/, "Fullscreen"],
               [/window\.float/, "Float window"], [/window\.pseudo/, "Pseudotile"],
               [/window\.move\(\{ direction/, "Move window " + d], [/focus\(\{ direction/, "Focus " + d],
               [/special:magic/, "Send to scratchpad"], [/toggle_special/, "Scratchpad"],
               [/window\.move\(\{ workspace/, "Send to workspace " + n], [/focus\(\{ workspace/, "Go to workspace " + n],
               [/hl\.dsp\.exit|\bexit\b|quit/, "Log out"],
               [/close-window/, "Close window"], [/fullscreen-window/, "Fullscreen"], [/maximize-column/, "Maximize column"],
               [/toggle-window-floating/, "Float window"], [/toggle-overview/, "Overview"],
               [/focus-workspace /, "Go to workspace " + n], [/move-column-to-workspace /, "Send to workspace " + n],
               [/set-volume.*\+/, "Volume up"], [/set-volume/, "Volume down"], [/SOURCE@ toggle/, "Mute microphone"], [/SINK@ toggle/, "Mute sound"],
               [/play-pause/, "Play / pause"], [/playerctl stop/, "Stop"], [/previous/, "Previous track"], [/playerctl next/, "Next track"],
               [/brightness\.sh up/, "Brightness up"], [/brightness\.sh down/, "Brightness down"],
               [/notifications dismiss/, "Dismiss notification"], [/notifications toggle/, "Notification centre"],
               [/zoom\.sh in/, "Zoom in"], [/zoom\.sh out/, "Zoom out"],
               [/next-wallpaper\.sh prev/, "Previous wallpaper"], [/next-wallpaper\.sh next/, "Next wallpaper"],
               [/launcher pick wallpaper/, "Wallpaper picker"], [/theme\.py personalize/, "Personalize"], [/osd caps/, "Caps Lock indicator"],
               [/ipc call lock lock/, "Lock screen"], [/ipc call clip/, "Clipboard history"], [/ipc call notes/, "Notes"],
               [/mon-brightness up/, "Brightness up"], [/mon-brightness down/, "Brightness down"],
               [/launcher toggle/, "Launcher"], [/alacritty|kitty|terminal/, "Terminal"], [/helium|firefox|chromium/, "Browser"],
               [/dolphin|nautilus|xdg-open/, "Files"], [/hyprlock/, "Lock screen"],
               [/panels toggle audio/, "Sound panel"], [/panels toggle net/, "Network panel"], [/panels toggle bt/, "Bluetooth panel"],
               [/screenshot|grim|hyprshot/, keys === "Print" ? "Screenshot, screen" : "Screenshot, area"]];
    for (const [re, name] of t) if (re.test(what)) return cap(name);
    const ipc = what.match(/ipc call (\w+) (\w+)/); if (ipc) return cap(ipc[1] + " " + ipc[2]);   // any other shell IPC bind: "Panels toggle"
    return (what.split(/[\s"]/).filter(x => x)[0] || what).replace(/-/g, " ");
  }
  property string capturing: ""   // keys of the bind being re-recorded
  function startCapture(keys) { capturing = keys; captureTimeout.restart(); refocus() }   // a click on the chip may have taken the focus: the keys come through the launcher input
  function endCapture() { capturing = "" }
  Timer { id: captureTimeout; interval: 8000; onTriggered: st.endCapture() }
  readonly property var scanNames: ({ 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0", 12: "Minus", 13: "Equal",
    16: "Q", 17: "W", 18: "E", 19: "R", 20: "T", 21: "Y", 22: "U", 23: "I", 24: "O", 25: "P", 26: "bracketleft", 27: "bracketright",
    30: "A", 31: "S", 32: "D", 33: "F", 34: "G", 35: "H", 36: "J", 37: "K", 38: "L", 39: "semicolon", 40: "apostrophe", 41: "grave", 43: "backslash",
    44: "Z", 45: "X", 46: "C", 47: "V", 48: "B", 49: "N", 50: "M", 51: "Comma", 52: "Period", 53: "Slash" })
  function keyName(e) {   // niri syntax: Mod+Ctrl+Alt+Shift+<xkb key name> (names are case-insensitive in niri)
    const special = { [Qt.Key_Space]: "Space", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Tab]: "Tab", [Qt.Key_Left]: "Left",
                      [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Print]: "Print", [Qt.Key_Home]: "Home",
                      [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down", [Qt.Key_Comma]: "Comma",
                      [Qt.Key_Period]: "Period", [Qt.Key_Slash]: "Slash", [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal", [Qt.Key_Plus]: "Plus" };
    let k = special[e.key];
    if (!k && e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12) k = "F" + (e.key - Qt.Key_F1 + 1);
    // letters, digits and punctuation by the physical key (evdev code = xkb keycode - 8), so a Cyrillic layout records the same names as niri binds
    if (!k) k = scanNames[e.nativeScanCode - 8];
    if (!k && e.key >= Qt.Key_A && e.key <= Qt.Key_Z) k = String.fromCharCode(e.key);
    if (!k && e.key >= Qt.Key_0 && e.key <= Qt.Key_9) k = String.fromCharCode(e.key);
    if (!k) return "";   // a lone modifier: keep waiting
    const mods = [];
    if (e.modifiers & Qt.MetaModifier) mods.push("Mod");
    if (e.modifiers & Qt.ControlModifier) mods.push("Ctrl");
    if (e.modifiers & Qt.AltModifier) mods.push("Alt");
    if (e.modifiers & Qt.ShiftModifier) mods.push("Shift");
    return mods.concat([k]).join("+");
  }

  // ---- model --------------------------------------------------------------------------------
  readonly property var tileNames: [["dark", "Dark"], ["night", "Night"], ["game", "Lite"], ["caffeine", "Caffeine"], ["profile", "Power"],
                                    ["mic", "Mic"], ["bt", "Bluetooth"], ["wifi", "Wi-Fi"], ["ai", "AI"]]
  readonly property var defaultTiles: ["dark", "night", "game", "caffeine", "profile", "mic", "bt", "wifi", "ai"]
  function apps(cat) { return DesktopEntries.applications.values.filter(a => !a.noDisplay && (a.categories || []).includes(cat)).map(a => [a.id, a.name]) }

  // ---- keyboard: kb_options is one xkb string, but switch-key / caps-remap / compose are independent settings_spec
  // 6.2 toggles - each has its own Prefs key, and this rebuilds the combined option string on every change.
  function kbOptions() {
    const parts = [Prefs.get("kb_switch", "grp:alt_shift_toggle")];
    const caps = Prefs.get("kb_caps", ""); if (caps) parts.push(caps);
    if (Prefs.get("kb_compose", false)) parts.push("compose:ralt");
    return parts.join(",");
  }
  function setKb(key, val) { Prefs.set(key, val); Look.setInput({ kb_options: kbOptions() }) }

  // ---- sound (settings_spec 4): device blacklist is a plain name list, same toggleIn() as everything else ----
  function audioLabel(n) { return n.description || n.nickname || n.name }
  function audioHidden(name) { return (Prefs.get("audio_hidden", []) || []).includes(name) }
  // settings_spec 4.4: EasyEffects' own virtual nodes are never a selectable "device" - physical audio is
  // proxied through them transparently, so they would just be a confusing duplicate in every list.
  readonly property var audioAll: Pipewire.nodes.values.filter(n => !n.isStream && n.audio && !(n.name || "").startsWith("easyeffects_"))
  function audioOuts() { return audioAll.filter(n => n.isSink && !audioHidden(n.name)) }
  function audioIns() { return audioAll.filter(n => !n.isSink && !(n.name || "").includes(".monitor") && !audioHidden(n.name)) }
  // meter/EE checks live only here. Set imperatively: as a binding it read `sections`, which reads the PipeWire streams that the
  // tracker below binds when soundOpen flips, so turning it on re-entered its own binding ("Binding loop … soundOpen").
  property bool soundOpen: false
  function updSoundOpen() { const v = !!sections[section] && sections[section].id === "sound" && filter === ""; if (v !== soundOpen) soundOpen = v }
  function audioBalance() {   // -50..50%, derived from the sink's per-channel volumes (no single "balance" property)
    const v = Audio.sink && Audio.sink.audio ? Audio.sink.audio.volumes : [];
    if (v.length < 2 || v[0] + v[1] === 0) return 0;
    return Math.round((v[1] - v[0]) / (v[0] + v[1]) * 100);
  }
  function setAudioBalance(b) {
    if (!Audio.sink || !Audio.sink.audio) return;
    const avg = Audio.volume, k = Math.max(-1, Math.min(1, b / 100));
    Audio.sink.audio.volumes = [avg * (1 - k), avg * (1 + k)];
  }
  onSoundOpenChanged: { if (soundOpen) { Sounds.scan(); listenFind.running = true } else if (listenId) listenSet(false) }

  // ---- network (settings_spec 5) -------------------------------------------------------
  readonly property var wired: Networking.devices.values.find(d => d.type !== DeviceType.Wifi)
  readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
  readonly property bool netOpen: ["network", "wifi"].indexOf(sections[section].id) >= 0 && filter === ""
  onNetOpenChanged: { if (netOpen && netDev) NetInfo.load(netDev); if (netOpen) { vpnRefresh.running = true; npLoad() } }
  property bool modemPresent: false
  Process { id: modemCheck; command: ["sh", "-c", "command -v mmcli >/dev/null && mmcli -L >/dev/null"]; onExited: code => st.modemPresent = code === 0 }
  Component.onCompleted: { modemCheck.running = true; updSoundOpen() }

  // ---- apps (settings_spec 8): 5.3 hide from launcher (our own NoDisplay override, reversible, user dir only),
  // 5.4 autostart toggle (Hidden= line in the user's own ~/.config/autostart/*.desktop). 5.2 (full installed-app
  // manager with per-app disk usage / uninstall) needs a destructive confirm-by-typing-name UI this engine's row
  // types don't have (settings_gaps.md) - not built.
  readonly property bool appsOpen: ["preferences", "storage"].indexOf(sections[section].id) >= 0 && filter === ""
  onAppsOpenChanged: if (appsOpen) autostartScan.running = true
  function appHidden(id) { return (Prefs.get("apps_hidden", []) || []).includes(id) }
  function toggleAppHidden(id) {
    const wasHidden = appHidden(id);
    toggleIn("apps_hidden", id, []);
    const path = Quickshell.env("HOME") + "/.local/share/applications/" + id;
    if (!wasHidden) Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")"; printf "[Desktop Entry]\\nNoDisplay=true\\n" > "$1"', "bash", path]);
    else Quickshell.execDetached(["rm", "-f", path]);
  }
  readonly property var appRows: {
    const seen = new Set(), out = [];
    for (const a of DesktopEntries.applications.values) if (!a.noDisplay && !seen.has(a.id)) { seen.add(a.id); out.push([a.id, a.name]) }
    for (const id of (Prefs.get("apps_hidden", []) || [])) if (!seen.has(id)) { seen.add(id); const e = DesktopEntries.byId(id); out.push([id, e ? e.name : id]) }
    return out.sort((x, y) => x[1].localeCompare(y[1]));
  }
  property var autostartApps: []   // [{ path, name, on }]
  Process {
    id: autostartScan
    command: ["bash", "-c", "for f in \"$HOME\"/.config/autostart/*.desktop; do [ -f \"$f\" ] || continue; " +
      "n=$(sed -n 's/^Name=//p' \"$f\" | head -1); h=$(sed -n 's/^Hidden=//p' \"$f\" | head -1); printf '%s\\t%s\\t%s\\n' \"$f\" \"${n:-$f}\" \"$h\"; done"]
    stdout: StdioCollector { onStreamFinished: {
      st.autostartApps = this.text.trim().split("\n").filter(l => l).map(l => { const p = l.split("\t"); return { path: p[0], name: p[1], on: p[2] !== "true" } });
    } }
  }
  function toggleAutostart(path, turnOn) {
    Quickshell.execDetached(["bash", "-c", turnOn ? 'sed -i "/^Hidden=/d" "$1"' : 'grep -q "^Hidden=" "$1" && sed -i "s/^Hidden=.*/Hidden=true/" "$1" || echo "Hidden=true" >> "$1"', "bash", path]);
    autostartScan.running = true;
  }

  // ---- system: disks, date & time, updates, maintenance, advanced (settings_spec 9 / 9.1) -------------------
  // Timezone (needs a city search box) and locale (LANG, needs the same) are shown read-only - this engine's
  // row types have no text-input widget (settings_gaps.md, same reason as hotspot name / SIM PIN fields).
  // Bootloader (9.1.4), package pinning (9.1.3) and GPU undervolt (9.1.5) are not built: this machine is
  // Arch/pacman + Limine (the Fedora note is outdated), and undervolt is a destructive sudo-only change
  // nobody asked for - rather than invent Fedora equivalents, left out and logged here.
  readonly property bool sysOpen: ["system", "storage", "gaming"].indexOf(sections[section].id) >= 0 && filter === ""
  onSysOpenChanged: if (sysOpen) { kernScan.running = true; driveScan.running = true; trimState.running = true; tzScan.running = true; localeScan.running = true; disksScan.running = true; mountScan.running = true; dateScan.running = true; updatesScan.running = true; pkgScan.running = true;
                                    gpuScan.running = true; netRemoteScan.running = true; servicesScan.running = true;
                                    swapScan.running = true }

  property var disks: []
  Process {
    id: disksScan
    command: ["bash", "-c", "lsblk -J -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,RM,FSUSED,FSUSE% 2>/dev/null"]
    stdout: StdioCollector { onStreamFinished: {
      try {
        const flat = [];
        const walk = n => { if (n.fstype && n.fstype !== "swap") flat.push(n); for (const c of n.children || []) walk(c) };
        for (const d of JSON.parse(this.text).blockdevices) walk(d);
        st.disks = flat;
      } catch (e) {}
    } }
  }
  function diskRows() {
    return disks.map(d => ({ type: "action", label: "/dev/" + d.name + (d.label ? " (" + d.label + ")" : ""),
      desc: d.size + " · " + d.fstype + (d.mountpoint ? " · " + d.mountpoint : " · not mounted") + (d["fsuse%"] ? " · " + d["fsuse%"] + " used" : ""),
      buttons: [].concat(d.mountpoint ? [["Open", () => Quickshell.execDetached(["xdg-open", d.mountpoint])]] : [],
                         d.rm || (d.mountpoint && !/^(\/|\/boot|\/boot\/efi|\/home)$/.test(d.mountpoint)) || !d.mountpoint ? [[d.mountpoint ? "Unmount" : "Mount", () => { diskMount(d.name, !!d.mountpoint) }]] : []) }));
  }
  function diskMount(name, mounted) { Quickshell.execDetached(["udisksctl", mounted ? "unmount" : "mount", "-b", "/dev/" + name]); disksTimer.restart() }
  Timer { id: disksTimer; interval: 1200; onTriggered: { disksScan.running = true; mountScan.running = true } }

  property var dateInfo: ({})
  Process {
    id: dateScan
    command: ["timedatectl", "show"]
    stdout: StdioCollector { onStreamFinished: {
      const m = {}; for (const l of this.text.split("\n")) { const i = l.indexOf("="); if (i > 0) m[l.slice(0, i)] = l.slice(i + 1) }
      st.dateInfo = m;
    } }
  }
  property var timezones: []
  Process {
    id: tzScan
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector { onStreamFinished: st.timezones = this.text.trim().split("\n").filter(l => l) }
  }
  property var locales: []
  property string sysLang: Quickshell.env("LANG") || "en_US.UTF-8"
  Process {
    id: localeScan
    command: ["localectl", "list-locales"]
    stdout: StdioCollector { onStreamFinished: st.locales = this.text.trim().split("\n").filter(l => /UTF-?8/i.test(l)) }
  }
  function setTimezone(z) { Quickshell.execDetached(["pkexec", "timedatectl", "set-timezone", z]); dateTimer.restart(); tzTimer.restart() }
  Timer { id: tzTimer; interval: 4000; onTriggered: dateScan.running = true }   // after the polkit prompt
  function setLocale(l) { Quickshell.execDetached(["pkexec", "localectl", "set-locale", "LANG=" + l]); sysLang = l }
  function setNtp(on) { Quickshell.execDetached(["timedatectl", "set-ntp", on ? "true" : "false"]); dateTimer.restart() }
  Timer { id: dateTimer; interval: 800; onTriggered: dateScan.running = true }

  property var updates: ({ pac: -1, fw: "", flatpak: false })
  Process {   // like checkupdates: sync a throw-away copy of the databases, the system ones stay untouched (no partial upgrade)
    id: updatesScan
    command: ["bash", "-c", "d=$(mktemp -d); ln -s /var/lib/pacman/local \"$d/local\"; if fakeroot -- pacman -Sy --dbpath \"$d\" --logfile /dev/null --disable-sandbox >/dev/null 2>&1; then pacman -Qu --dbpath \"$d\" 2>/dev/null | wc -l; else echo -2; fi; rm -rf \"$d\"; "
      + "echo; "
      + "command -v flatpak >/dev/null && echo yes || echo no"]
    stdout: StdioCollector { onStreamFinished: {
      const l = this.text.split("\n"); st.updates = { pac: Number(l[0] || 0), fw: (l[1] || "").trim(), flatpak: (l[2] || "").trim() === "yes" };
    } }
  }
  property var pkgs: ({ run: "", kernels: "", unused: -1 })   // kernels in use / installed, packages nothing needs any more (pacman -Qdtq)
  Process {
    id: pkgScan
    command: ["bash", "-c", "uname -r; pacman -Qq | grep -E '^linux(-zen|-lts|-hardened|-rt|-cachyos[a-z0-9-]*)?$' | grep -v headers | xargs -r pacman -Q | sed 's/ /-/;s/^linux-//' ; "
      + "echo ---; pacman -Qdtq 2>/dev/null | wc -l"]
    stdout: StdioCollector { onStreamFinished: {
      const t = this.text.split("\n"), i = t.indexOf("---");
      st.pkgs = { run: t[0], kernels: t.slice(1, i).filter(x => x).join("  ·  "), unused: Number(t[i + 1] || 0) };
    } }
  }
  property bool autoremoveArmed: false
  Timer { id: armTimer; interval: 5000; onTriggered: st.autoremoveArmed = false }
  Process { id: autoremoveRun; command: ["alacritty", "-e", "sh", "-c", "sudo pacman -Rns $(pacman -Qdtq); echo; read -p 'Press Enter to close' x"]; onExited: pkgScan.running = true }   // pacman lists what goes and asks
  property real updProgress: -2      // -2 idle, -1 running without numbers, 0..1 a share
  property string updText: ""
  Process {   // the terminal shows pacman's own output, news and questions: an Arch upgrade is not a thing to run blind
    id: sysUpgrade
    command: ["alacritty", "-e", "sh", "-c", "sudo pacman -Syu; echo; read -p 'Press Enter to close' x"]
    onStarted: { st.updText = "Running in the terminal…" }
    onExited: { st.updText = "Terminal closed"; updatesScan.running = true }
  }
  Process { id: flatpakUpgrade; command: ["flatpak", "update", "-y"]; onExited: updatesScan.running = true }

  // sound: device lists with Hide / Show, "listen to this device" (a loopback module, only while this page is open), per-app volume
  function deviceRows(out) {
    const all = audioAll.filter(n => out ? n.isSink : (!n.isSink && !(n.name || "").includes(".monitor")));
    const cur = out ? Audio.sink : Audio.source;
    const use = n => { if (out) Pipewire.preferredDefaultAudioSink = n; else Pipewire.preferredDefaultAudioSource = n };
    const vis = all.filter(n => !audioHidden(n.name)), hid = all.filter(n => audioHidden(n.name));
    return [header(out ? "Output devices" : "Input devices")].concat(
      vis.map(n => ({ type: "action", label: audioLabel(n), desc: cur && cur.name === n.name ? "In use" : "",
                      buttons: (cur && cur.name === n.name ? [] : [["Use", () => use(n)]]).concat([["Hide", () => toggleIn("audio_hidden", n.name, [])]]) })),
      hid.length ? [header("Hidden (" + hid.length + ")")].concat(hid.map(n => ({ type: "action", label: audioLabel(n), desc: "",
                      buttons: [["Show", () => toggleIn("audio_hidden", n.name, [])]] }))) : []);
  }
  property string listenId: ""
  function listenSet(on) {
    if (on && Audio.source && Audio.sink) { listenLoad.command = ["pactl", "load-module", "module-loopback", "source=" + Audio.source.name, "sink=" + Audio.sink.name,
                                                                   "latency_msec=30", "sink_input_properties=media.name=lwts-listen"]; listenLoad.running = true }
    else if (!on && listenId) { listenUnload.command = ["pactl", "unload-module", listenId]; listenUnload.running = true }
  }
  Process { id: listenLoad; stdout: StdioCollector { onStreamFinished: st.listenId = this.text.trim() } }
  Process { id: listenUnload; onExited: st.listenId = "" }
  Process { id: listenFind; command: ["bash", "-c", "pactl list short modules | awk '/lwts-listen/ {print $1; exit}'"]
            stdout: StdioCollector { onStreamFinished: st.listenId = this.text.trim() } }
  // Input: the XKB catalog (layouts, switch options) read from base.lst, layout list editing, keyboard map highlights
  readonly property bool inputOpen: sections[section].id === "devices" && filter === ""
  // Gamepad (Input -> Gamepad, only while a pad is connected): pads + centring live in services/PadCal.qml
  readonly property var pads: PadCal.pads
  property int padIdx: 0   // which of the connected pads the tab shows
  readonly property var curPad: pads.length ? pads[Math.min(padIdx, pads.length - 1)] : null
  // button rebinding: pick the game button, press the pad button that should act as it (PadSource below catches the key)
  property string bindTarget: "X"
  property bool bindWait: false
  readonly property var bindBtns: [["A", 304], ["B", 305], ["X", 307], ["Y", 308], ["LB", 310], ["RB", 311], ["Back", 314], ["Start", 315], ["L3", 317], ["R3", 318]]
  function bindCode(n) { const b = bindBtns.find(x => x[0] === n); return b ? b[1] : 0 }
  function bindName(c) { const b = bindBtns.find(x => x[1] === c); return b ? b[0] : String(c) }
  // Steam style: "Bind all" asks for every button in turn (A, B, X, ...); Skip leaves one out, Cancel changes nothing
  property int bindSeq: -1       // index in bindBtns being asked, -1 = not running
  property var seqMap: ({})      // physical key -> game key, filled as the user presses
  function seqStart() { bindWait = false; seqMap = {}; bindSeq = 0 }
  function seqNext() { bindSeq++; if (bindSeq >= bindBtns.length) seqFinish() }
  function seqPress(code) { if (seqMap[code] !== undefined) return; seqMap[code] = bindBtns[bindSeq][1]; seqNext() }
  function seqFinish() {
    const m = Object.assign({}, seqMap), claimed = Object.keys(m).map(k => m[k]);
    if (!claimed.length || !curPad) { bindSeq = -1; return }
    const free = bindBtns.map(b => b[1]).filter(c => claimed.indexOf(c) < 0);   // skipped game buttons
    bindBtns.forEach(b => { if (m[b[1]] === undefined && claimed.indexOf(b[1]) >= 0 && free.length) m[b[1]] = free.shift() })   // an untouched key whose code was taken: no duplicates
    PadCal.setBtnMap(curPad, m);
    bindSeq = -1;
  }
  PadSource {
    pad: st.bindWait || st.bindSeq >= 0 ? st.curPad : null
    active: st.bindWait || st.bindSeq >= 0
    onPress: code => { if (st.bindSeq >= 0) st.seqPress(code); else { if (st.curPad) PadCal.rebind(st.curPad, code, st.bindCode(st.bindTarget)); st.bindWait = false } }
  }
  function padRumble(strong, weak) {   // through the virtual pad while the layer holds the real one (the service forwards it)
    if (!curPad) return;
    const dev = PadCal.layerRun ? PadCal.virtOf[curPad.path] : curPad.path;
    if (dev) Quickshell.execDetached(["lwts-pad", "rumble", dev, String(strong), String(weak), "500"]);
  }
  // Big Picture style: pick a part (segments) -> its live picture (GamepadView) -> only its settings
  property string padPart: "o"
  function padRows() {
    if (!pads.length) return [];
    const p = curPad, t = PadCal.tune(p.id), sticks = PadCal.sticks(p), hasTr = PadCal.triggers(p).length > 0;
    void Prefs.get(PadCal.key(p.id), "");   // re-evaluate the rows when the calibration changes
    if (PadCal.wiz !== "")   // calibration: the tab is only the wizard and its buttons
      return [tab("Gamepad"), header(PadCal.padName(p) + " · calibration"), { type: "padwiz", label: "", desc: "" },
        PadCal.wizStage === "review"
          ? { type: "action", label: "Calibration result", desc: "", buttons: [["Save", () => PadCal.wizCmd("save")], ["Again", () => PadCal.wizCmd("again")], ["Discard", () => PadCal.wiz = ""]] }
          : { type: "action", label: "Calibration", desc: "", buttons: [["Skip step", () => PadCal.wizCmd("skip")], ["Cancel", () => PadCal.wiz = ""]] }];
    const parts = [["o", "Overview"], ["l", "Left stick"], ["r", "Right stick"]].concat(hasTr ? [["t", "Triggers"]] : [], [["b", "Buttons"]]);
    const part = parts.some(x => x[0] === padPart) ? padPart : "o";
    const pct = v => (v > 0 ? "+" : "") + v.toFixed(2) + "%";
    const off = !PadCal.layerRun && part !== "o" ? [info("Layer is off", "Games read the pad as is: turn the layer on in Overview")] : [];
    const tuneSlider = (label, desc, name, steps, fmt) => Object.assign(slider(label, desc, steps, fmt === "x" ? "" : "%", () => t[name], v => PadCal.setTune(p, name, v)),
                                                                        fmt === "x" ? { format: v => v === 1 ? "Linear" : "×" + v } : {});
    let rows;
    if (part === "o") {   // only what is needed: the layer, calibration, a rumble test
      rows = (pads.length > 1 ? [cycle("Gamepad", PadCal.mode === "one" && PadCal.activePath === p.path ? "Games use this one now" : PadCal.mode === "all" ? "Player " + (padIdx + 1) : "",
                                       pads.map((q, i) => [i, PadCal.padName(q)]), () => padIdx, v => { padIdx = Number(v); bindWait = false }),
                                 choice("Several pads", PadCal.mode === "one" ? "One pad for games: the one you touched last" : "Each pad is its own player, in priority order",
                                        [["one", "Last used"], ["all", "Each its own"]], () => PadCal.mode, v => Prefs.set("pad_mode", v)),
                                 { type: "action", label: "Priority", desc: pads.map(q => PadCal.padName(q)).join("  →  "), buttons: padIdx > 0 ? [["Make first", () => { PadCal.makeFirst(p); padIdx = 0 }]] : [] }] : [])
        .concat([choice("Gamepad layer", PadCal.layer ? (PadCal.layerRun ? "Games get the corrected pad" : "Waiting for the lwts-padd service") : "Games read the pad as is",
                     [["off", "Off"], ["on", "On"]], () => PadCal.layer ? "on" : "off", v => Prefs.set("pad_layer", v === "on")),
        { type: "action", label: "Calibrate sticks and triggers", desc: t.lrec || t.rrec ? "Recommended deadzones: left " + t.lrec + "% · right " + t.rrec + "%" : "",
          buttons: [["Start", () => PadCal.wiz = "on"], ["Reset", () => PadCal.reset(p)]].concat(t.lrec || t.rrec ? [["Apply deadzones", () => PadCal.setTunes(p, { ldz: t.lrec, rdz: t.rrec })]] : []) }]);
    } else if (part === "b") {   // rebinding: the map is per pad model, applied by the layer (lwts-padd) to the virtual pad
      const m = PadCal.btnMap(p.id), ch = Object.keys(m).filter(k => m[k] !== Number(k)).map(k => bindName(Number(k)) + "→" + bindName(m[k]));
      rows = bindSeq >= 0 ? off.concat([{ type: "action", label: "Press the button for " + bindBtns[bindSeq][0] + "  (" + (bindSeq + 1) + " / " + bindBtns.length + ")", desc: "",
          buttons: [["Skip", () => seqNext()], ["Cancel", () => bindSeq = -1]] }]) : off.concat([
        cycle("Game button", "", bindBtns.map(b => [b[0], b[0]]), () => bindTarget, v => { bindTarget = v; bindWait = false }),
        { type: "action", label: bindWait ? "Press the pad button for " + bindTarget + "…" : "Changed: " + (ch.length ? ch.join("  ") : "none"), desc: "",
          buttons: [["Bind all", () => seqStart()], [bindWait ? "Cancel" : "One button", () => bindWait = !bindWait], ["Swap X ↔ Y", () => PadCal.swapXY(p)], ["Reset", () => { bindWait = false; PadCal.setBtnMap(p, {}) }]] },
        { type: "action", label: "Vibration test", desc: "", buttons: [["Strong", () => padRumble(50000, 0)], ["Weak", () => padRumble(0, 50000)], ["Both", () => padRumble(50000, 50000)]] },
        input("Name", "", () => PadCal.padName(p), v => PadCal.setPadName(p, v), { placeholder: p.name })]);
    } else if (part === "l" || part === "r") {   // no headers, no hints: the tab must fit without scrolling (user's iron rule)
      const sd = part, cs = sticks[sd === "l" ? 0 : 1];
      rows = off.concat([
        tuneSlider(t[sd + "rec"] ? "Deadzone · recommended " + t[sd + "rec"] + "%" : "Deadzone", "", sd + "dz", [0, 2, 4, 6, 8, 10, 12, 15, 20, 25, 30]),
        tuneSlider("Outer deadzone", "", sd + "out", [0, 2, 4, 6, 8, 10, 15, 20]),
        tuneSlider("Curve", "", sd + "curve", [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], "x"),
        tuneSlider("Anti-deadzone", "", sd + "ad", [0, 2, 4, 6, 8, 10, 12, 15, 20, 25]),
        { type: "action", label: "Centre  X " + pct(PadCal.offset(p, cs[0])) + " · Y " + pct(PadCal.offset(p, cs[1])), desc: "",
          buttons: [["X −", () => PadCal.nudge(p, cs[0], -1)], ["X +", () => PadCal.nudge(p, cs[0], 1)], ["Y −", () => PadCal.nudge(p, cs[1], -1)], ["Y +", () => PadCal.nudge(p, cs[1], 1)]] },
        Object.assign(slider("Jitter filter · both sticks", "", [0, 0.5, 1, 1.5, 2, 3, 4], "%", () => t.jit, v => PadCal.setTune(p, "jit", v)), { format: v => v ? v + "%" : "Off" })]);
    } else {
      rows = off.concat(...[["LT", "l"], ["RT", "r"]].map(n => [
        tuneSlider(n[0] + " start", "", n[1] + "ts", [0, 2, 5, 8, 10, 15, 20, 30, 40, 50]),
        tuneSlider(n[0] + " full press", "", n[1] + "te", [50, 60, 70, 80, 85, 90, 95, 100])]));
    }
    return [tab("Gamepad"), { type: "choice", label: "", desc: "", options: parts, get: () => part, set: v => st.padPart = v },
            { type: "padview", label: "", desc: "", part: part === "b" ? "o" : part }].concat(rows);
  }


  property var kbLayouts: []   // [[code, name]]
  property var kbGrp: []       // [[grp:..., name]]
  Process {
    id: kbCat
    command: ["awk", '/^! layout/{m="l";next} /^! variant/{m="v";next} /^! option/{m="o";next} /^!/{m=""} m=="l" && NF {c=$1; $1=""; sub(/^ +/,""); print "L\t" c "\t" $0} m=="o" && $1 ~ /^grp:/ {c=$1; $1=""; sub(/^ +/,""); print "G\t" c "\t" $0}',
              "/usr/share/X11/xkb/rules/base.lst"]
    stdout: StdioCollector { onStreamFinished: {
      const L = [], G = [];
      for (const l of this.text.trim().split("\n")) { const p = l.split("\t"); if (p[0] === "L") L.push([p[1], p[2]]); else if (p[0] === "G") G.push([p[1], p[2]]) }
      st.kbLayouts = L.sort((a, b) => a[1].localeCompare(b[1])); st.kbGrp = G;
    } }
  }
  onInputOpenChanged: { if (inputOpen && kbLayouts.length === 0) kbCat.running = true; if (!inputOpen) PadCal.wiz = "" }   // leaving Input ends a calibration (nothing saved)
  function kbLayoutRows() {
    const cur = String(Prefs.get("kb_layout", "us,ua,ru")).split(",").filter(x => x);
    const name = c => (kbLayouts.find(l => l[0] === c) || [c, c])[1];
    const set = l => Look.setInput({ kb_layout: l.join(",") });
    const move = (i, d) => { const l = cur.slice(); const t = l[i]; l[i] = l[i + d]; l[i + d] = t; set(l) };
    return cur.map((c, i) => ({ type: "action", label: name(c), desc: c + (i === 0 ? " · first, used at login" : ""),
      buttons: [].concat(i > 0 ? [["Up", () => move(i, -1)]] : [], i < cur.length - 1 ? [["Down", () => move(i, 1)]] : [],
                         cur.length > 1 ? [["Remove", () => set(cur.filter((_, j) => j !== i))]] : []) }))
      .concat([cycle("Add a layout", "", [["", "Choose…"]].concat(kbLayouts.filter(l => cur.indexOf(l[0]) < 0)),
                     () => "", v => { if (v) set(cur.concat([v])) })]);
  }
  function kbSwitchOptions() { const cur = Prefs.get("kb_switch", "grp:alt_shift_toggle"); return kbGrp.some(g => g[0] === cur) ? kbGrp : [[cur, cur]].concat(kbGrp) }
  readonly property var kbKeys: {   // the mini keyboard: [evdev code, legend, width in keys], one array per row
    const rows = [
      [[1, "Esc", 1], [0, "", 0.5], [59, "F1", 1], [60, "F2", 1], [61, "F3", 1], [62, "F4", 1], [0, "", 0.5], [63, "F5", 1], [64, "F6", 1], [65, "F7", 1], [66, "F8", 1], [0, "", 0.5], [67, "F9", 1], [68, "F10", 1], [87, "F11", 1], [88, "F12", 1]],
      [[41, "`", 1], [2, "1", 1], [3, "2", 1], [4, "3", 1], [5, "4", 1], [6, "5", 1], [7, "6", 1], [8, "7", 1], [9, "8", 1], [10, "9", 1], [11, "0", 1], [12, "-", 1], [13, "=", 1], [14, "Bksp", 2]],
      [[15, "Tab", 1.5], [16, "Q", 1], [17, "W", 1], [18, "E", 1], [19, "R", 1], [20, "T", 1], [21, "Y", 1], [22, "U", 1], [23, "I", 1], [24, "O", 1], [25, "P", 1], [26, "[", 1], [27, "]", 1], [43, "\\", 1.5]],
      [[58, "Caps", 1.75], [30, "A", 1], [31, "S", 1], [32, "D", 1], [33, "F", 1], [34, "G", 1], [35, "H", 1], [36, "J", 1], [37, "K", 1], [38, "L", 1], [39, ";", 1], [40, "'", 1], [28, "Enter", 2.25]],
      [[42, "Shift", 2.25], [44, "Z", 1], [45, "X", 1], [46, "C", 1], [47, "V", 1], [48, "B", 1], [49, "N", 1], [50, "M", 1], [51, ",", 1], [52, ".", 1], [53, "/", 1], [54, "Shift", 2.75]],
      [[29, "Ctrl", 1.25], [125, "Super", 1.25], [56, "Alt", 1.25], [57, "", 6.25], [100, "AltGr", 1.25], [126, "Super", 1.25], [127, "Menu", 1.25], [97, "Ctrl", 1.25]]];
    const out = []; rows.forEach((row, y) => { let x = 0; for (const k of row) { if (k[0]) out.push({ code: k[0], label: k[1], x, y, w: k[2] }); x += k[2] } });
    return out;
  }
  property var kbLit: ({})
  function kbPress(e) { const c = e.nativeScanCode - 8; if (c > 0) { const o = Object.assign({}, kbLit); o[c] = true; kbLit = o; kbLitTimer.restart() } }
  Timer { id: kbLitTimer; interval: 350; onTriggered: st.kbLit = ({}) }

  // Hotkeys, GNOME style: folded groups (a search shows everything); the rows are the same `hotkey` rows as before
  property var hkOpen: ({ "Apps and panels": true })
  function hkGroup(name) {
    return /window|Close|Kill|Maximize|Fullscreen|Float|Pseudo|Focus|Move|Resize/i.test(name) ? "Windows"
         : /workspace|Scratchpad/i.test(name) ? "Workspaces"
         : /Volume|Mute|Play|Stop|track|Brightness/i.test(name) ? "Sound and screen"
         : /Log out|Lock|Suspend|Power/i.test(name) ? "Session" : "Apps and panels";
  }
  readonly property var hkBy: {   // parsed once per binds change: rebuilding it on every search keystroke cost ~15 ms
    const by = {};
    for (const b of binds) { const nm = nice(b.what, b.keys), g = hkGroup(nm); (by[g] = by[g] || []).push({ type: "hotkey", label: nm,
        desc: /hl\.dsp|^mod |^"/.test(b.what) ? "" : b.what.length > 60 ? b.what.slice(0, 60) + "…" : b.what, keys: b.keys, removed: !!b.removed, def: (!b.removed && defaultKeys[b.what] && defaultKeys[b.what] !== b.keys) ? defaultKeys[b.what] : "" }) }
    return by;
  }
  function hotkeyRows() {
    const order = ["Apps and panels", "Windows", "Workspaces", "Sound and screen", "Session"], by = hkBy;
    const out = [];
    for (const g of order) {
      const l = by[g]; if (!l) continue;
      const open = filter !== "" || !!hkOpen[g];
      out.push({ type: "action", label: g, desc: l.length + (l.length === 1 ? " shortcut" : " shortcuts"), buttons: [[open ? "Hide" : "Show", () => { const o = Object.assign({}, hkOpen); o[g] = !o[g]; hkOpen = o }]] });
      if (open) for (const r of l) out.push(r);
    }
    return out;
  }
  // ---- Devices: Bluetooth (Quickshell.Bluetooth) and printers (CUPS: lpstat / lpadmin / lp / cancel) ----
  readonly property bool devicesOpen: sections[section].id === "bluetooth" && filter === ""
  onDevicesOpenChanged: if (devicesOpen) { if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) Bluetooth.defaultAdapter.discovering = true } else if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) Bluetooth.defaultAdapter.discovering = false
  function btRows() {
    const a = Bluetooth.defaultAdapter;
    if (!a) return [info("Bluetooth", "No adapter found")];
    const devs = Bluetooth.devices.values.filter(d => d.name || d.deviceName).slice().sort((x, y) => (y.connected - x.connected) || (y.paired - x.paired) || ((x.name || "").localeCompare(y.name || "")));
    const rows = [choice("Bluetooth", "", [["off", "Off"], ["on", "On"]], () => a.enabled ? "on" : "off", v => { a.enabled = v === "on" }),
                  choice("Look for new devices", "", [["off", "Off"], ["on", "On"]], () => a.discovering ? "on" : "off", v => { a.discovering = v === "on" })];
    for (const d of devs) {
      const bat = d.batteryAvailable ? " · battery " + Math.round(d.battery * 100) + "%" : "";
      rows.push({ type: "action", label: d.name || d.deviceName, desc: (d.connected ? "Connected" : d.paired ? "Paired" : "Nearby") + bat,
        buttons: [d.connected ? ["Disconnect", () => d.disconnect()] : d.paired ? ["Connect", () => d.connect()] : ["Pair", () => d.pair()]].concat(d.paired ? [["Forget", () => d.forget()]] : []) });
    }
    return rows;
  }
  // Disks: physical drives with a health check (smartctl through lwts-priv), mount / eject / open, weekly TRIM
  property var drives: []     // [{ name, model, size, kind }]
  property var smartOut: ({})
  property string smartBusy: ""
  property string trimTimer: "?"   // enabled | disabled | ?
  property string trimMsg: ""
  Process {
    id: driveScan
    command: ["lsblk", "-J", "-d", "-o", "NAME,MODEL,SIZE,ROTA,TRAN,TYPE"]
    stdout: StdioCollector { onStreamFinished: {
      try { st.drives = JSON.parse(this.text).blockdevices.filter(d => d.type === "disk" && !/^(zram|loop|sr)/.test(d.name))
              .map(d => ({ name: d.name, model: (d.model || d.name).trim(), size: d.size, kind: d.tran === "nvme" ? "NVMe" : d.rota ? "HDD" : d.tran === "usb" ? "USB" : "SSD" })) } catch (e) {}
    } }
  }
  Process { id: trimState; command: ["systemctl", "is-enabled", "fstrim.timer"]; stdout: StdioCollector { onStreamFinished: st.trimTimer = this.text.trim() === "enabled" ? "enabled" : "disabled" } }
  Process { id: trimRun; onExited: code => { st.trimMsg = code === 0 ? "Done" : "Not done (is the helper updated?)"; trimState.running = true } }
  Process {
    id: smartRun
    property string dev: ""
    stdout: StdioCollector { onStreamFinished: {
      const t = this.text, g = re => { const m = t.match(re); return m ? m[1] : "" };
      const health = g(/overall-health[^\n]*?:\s*(\w+)/) || g(/SMART Health Status:\s*(\w+)/);
      const parts = [health, g(/Temperature:\s+(\d+) Celsius/) ? g(/Temperature:\s+(\d+) Celsius/) + " °C" : "", g(/Percentage Used:\s+(\d+)%/) ? g(/Percentage Used:\s+(\d+)%/) + "% worn" : "",
                     g(/Power[ _]On[ _]Hours:?\s+([\d,]+)/) ? g(/Power[ _]On[ _]Hours:?\s+([\d,]+)/) + " h" : "",
                     g(/Media and Data Integrity Errors:\s+(\d+)/) ? g(/Media and Data Integrity Errors:\s+(\d+)/) + " media errors" : ""].filter(x => x);
      const o = Object.assign({}, st.smartOut); o[smartRun.dev] = parts.length ? parts.join(" · ") : "No answer (the helper needs the update, or smartctl cannot read this drive)"; st.smartOut = o; st.smartBusy = "";
    } }
  }
  // Storage v5: space as bars, mounting as a list of what is mounted where and with which options (udisks level, no fstab edits)
  property var mounts: []
  Process {
    id: mountScan
    command: ["bash", "-c", "findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null"]
    stdout: StdioCollector { onStreamFinished: {
      st.mounts = this.text.trim().split("\n").map(l => l.split(" ")).filter(f => f.length >= 4 && /^(btrfs|ext[234]|xfs|vfat|exfat|ntfs3?|fuseblk|f2fs|cifs|nfs4?|fuse\..*)$/.test(f[2]) && !/^\/(var\/lib|proc|sys|run\/credentials)/.test(f[0]))
        .map(f => ({ target: f[0], source: f[1].replace(/\[.*\]/, ""), fstype: f[2], opts: f[3] }));
    } }
  }
  function pctOf(d) { const v = parseFloat(String(d["fsuse%"] || "").replace("%", "")); return isNaN(v) ? -1 : v / 100 }
  function usageRows() {
    const used = disks.filter(d => d.mountpoint);
    if (!used.length) return [info("Space", "No mounted filesystems found")];
    return used.map(d => ({ type: "progress", label: (d.label || d.name) + " · " + d.mountpoint, value: Math.max(0, pctOf(d)),
                            text: (d.fsused || "?") + " of " + d.size + " · " + d.fstype + (pctOf(d) >= 0 ? " · " + Math.round(pctOf(d) * 100) + "%" : "") }));
  }
  function remount(target, opt) { Quickshell.execDetached(["pkexec", "/usr/local/libexec/lwts-priv", "remount", target, opt]); mountsTimer.restart() }
  Timer { id: mountsTimer; interval: 1500; onTriggered: mountScan.running = true }
  function mountRows() {   // one block per filesystem: where it is mounted, then the options you can change (applied now, not written to fstab)
    const on = disks.filter(d => d.mountpoint);
    if (!on.length) return [info("Mounted", "Nothing found")];
    let out = [];
    for (const d of on) {
      const m = mounts.find(x => x.target === d.mountpoint), o = m ? m.opts.split(",") : [];
      const safe = /^(\/|\/boot|\/boot\/efi|\/home|\/var|\/usr|\/nix)$/.test(d.mountpoint), tg = d.mountpoint;
      out.push(header((d.label || d.name) + " · " + tg + " · " + d.fstype));
      out.push({ type: "action", label: "Mounted at " + tg, desc: d.size + (d.fsused ? " · " + d.fsused + " used" : ""),
                 buttons: [["Open", () => Quickshell.execDetached(["xdg-open", tg])]].concat(safe ? [] : [["Unmount", () => diskMount(d.name, true)]]) });
      if (!m || tg === "/") continue;
      if (/^(btrfs|ext[234]|xfs|f2fs)$/.test(d.fstype))
        out.push(choice("Access time", "noatime saves writes on SSDs", [["relatime", "Relatime"], ["noatime", "No atime"]],
                        () => o.indexOf("noatime") >= 0 ? "noatime" : "relatime", v => remount(tg, v)));
      if (d.fstype === "btrfs")
        out.push(choice("Compression", "New writes are compressed; existing data stays as it is", [["compress=no", "Off"], ["compress=zstd:1", "Light"], ["compress=zstd:3", "Strong"]],
                        () => o.find(x => /^compress/.test(x)) === "compress=zstd:3" ? "compress=zstd:3" : o.some(x => /^compress/.test(x)) ? "compress=zstd:1" : "compress=no", v => remount(tg, v)));
      if (!safe)
        out.push(choice("Access", "Read-only protects the drive's files", [["rw", "Read and write"], ["ro", "Read only"]],
                        () => o.indexOf("ro") >= 0 ? "ro" : "rw", v => remount(tg, v)));
    }
    return out;
  }
  function unmountedRows() {
    const free = disks.filter(d => !d.mountpoint && !/^(crypto_LUKS|LVM2_member|linux_raid_member)$/.test(d.fstype));   // containers are opened elsewhere; only filesystems can be mounted
    if (!free.length) return [info("Not mounted", "Every filesystem is mounted")];
    return free.map(d => ({ type: "action", label: "/dev/" + d.name + (d.label ? " (" + d.label + ")" : ""), desc: d.size + " · " + d.fstype,
                            buttons: [["Mount", () => diskMount(d.name, false)]] }));
  }
  function shareRows() {
    const sh = mounts.filter(m => /^(cifs|nfs4?)$/.test(m.fstype));
    return sh.length ? sh.map(m => ({ type: "action", label: m.target, desc: m.source + " · " + m.fstype, buttons: [["Open", () => Quickshell.execDetached(["xdg-open", m.target])]] }))
                     : [info("Network shares", "None mounted")];
  }
  function driveRows() {
    if (!drives.length) return [info("Drives", "None found")];
    return drives.map(d => ({ type: "action", label: d.model + " · " + d.size, desc: d.kind + " · /dev/" + d.name + (smartBusy === d.name ? " · checking…" : smartOut[d.name] ? " · " + smartOut[d.name] : ""),
      buttons: [["Check health", () => { smartBusy = d.name; smartRun.dev = d.name; smartRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "smart", d.name]; smartRun.running = true }]] }));
  }
  function trimRows() {
    return [header("TRIM"),
      choice("Weekly TRIM", "Keeps SSDs fast", [["off", "Off"], ["on", "On"]], () => trimTimer === "enabled" ? "on" : "off",
             v => { trimRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "service", v === "on" ? "enable" : "disable", "fstrim.timer"]; trimRun.running = true }),
      { type: "action", label: "Trim now", desc: trimMsg || "Runs fstrim on every mounted filesystem", buttons: [["Trim", () => { trimMsg = "Running…"; trimRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "trim"]; trimRun.running = true }]] }];
  }

  property var gpu: ({})
  Process {
    id: gpuScan
    command: ["bash", "-c", "h=$(ls -d /sys/class/drm/card*/device/hwmon/hwmon* 2>/dev/null | head -1); "
      + "[ -n \"$h\" ] && { cat \"$h/temp1_input\" 2>/dev/null; cat \"$h/power1_average\" 2>/dev/null; cat \"$h/freq1_input\" 2>/dev/null; cat \"$h/fan1_input\" 2>/dev/null; }"]
    stdout: StdioCollector { onStreamFinished: {
      const l = this.text.trim().split("\n");
      const g = { temp: l[0] ? Math.round(Number(l[0]) / 1000) : null, power: l[1] ? Math.round(Number(l[1]) / 1e6) : null,
                  freq: l[2] ? Math.round(Number(l[2]) / 1e6) : null, fan: l[3] ? Number(l[3]) : null };
      if (JSON.stringify(g) !== JSON.stringify(st.gpu)) st.gpu = g;   // a new object rebuilds every section
    } }
  }
  Timer { id: gpuTimer; interval: 2000; running: sysOpen && (groups[group] || {}).label === "GPU"; repeat: true; onTriggered: gpuScan.running = true }

  readonly property string openId: filter === "" ? sections[section].id : ""
  Binding { target: Modules; property: "openSection"; value: st.openId }   // modules see which category is open (Modules.openSection)
  property var netRemote: ({})
  Process {
    id: netRemoteScan
    command: ["bash", "-c", "systemctl is-active sshd 2>/dev/null; systemctl is-enabled sshd 2>/dev/null; "
      + "systemctl is-enabled nftables 2>/dev/null; d=$(resolvectl status 2>/dev/null | grep -m1 'DNS Servers' | sed 's/.*: *//'); "
      + "[ -n \"$d\" ] || d=$(awk '/^nameserver/ {printf \"%s \", $2}' /etc/resolv.conf); echo \"$d\"; "
      + "findmnt -rn -t cifs,smb3,nfs,nfs4 -o TARGET | head -1"]
    stdout: StdioCollector { onStreamFinished: {
      const l = this.text.split("\n");
      st.netRemote = { sshActive: l[0] === "active", sshEnabled: l[1] === "enabled", fwEnabled: l[2] === "enabled", dns: l[3] || "", share: l[4] || "" };
    } }
  }
  function toggleSsh(on) { Quickshell.execDetached(["pkexec", "systemctl", on ? "enable" : "disable", "--now", "sshd"]); netRemoteTimer.restart() }
  Timer { id: netRemoteTimer; interval: 1200; onTriggered: netRemoteScan.running = true }

  // ---- Gaming -> Kernels (settings_redesign 4.12 item 2): list, install / remove with the guards of lwts-priv `kernel` ----
  property var kern: ({})
  property string kernBusy: ""
  property string kernMsg: ""
  Process {
    id: kernScan
    command: ["bash", "-c", "KL=\"linux linux-zen linux-lts linux-hardened linux-rt linux-rt-lts linux-cachyos linux-cachyos-bore-lto linux-cachyos-bore linux-cachyos-eevdf-lto linux-cachyos-eevdf linux-cachyos-bmq-lto linux-cachyos-bmq linux-cachyos-server-lto linux-cachyos-server linux-cachyos-lts-lto linux-cachyos-lts linux-cachyos-hardened-lto linux-cachyos-hardened linux-cachyos-rt-bore-lto linux-cachyos-rt-bore linux-cachyos-deckify-lto linux-cachyos-deckify\"; echo \"run=$(cat /usr/lib/modules/$(uname -r)/pkgbase 2>/dev/null)\"; echo \"free=$(df -m --output=avail /boot | tail -1 | tr -d ' ')\"; echo \"boot=$(df -m --output=size,used,avail /boot | tail -1)\"; pacman -Si $KL 2>/dev/null | awk -F' *: *' -v inst=\"$(pacman -Qq | tr '\\n' ' ')\" '/^Name/{n=$2; skip=(n in seen); seen[n]=1} !skip&&/^Version/{v[n]=$2} !skip&&/^Installed Size/{z[n]=$2} END{for(n in v) print \"k|\" n \"|\" (index(\" \" inst, \" \" n \" \")>0 ? 1 : 0) \"|\" v[n] \"|\" z[n]}'"]
    stdout: StdioCollector { onStreamFinished: {
      const k = { list: [] };
      for (const l of this.text.split("\n")) {
        if (l.startsWith("run=")) k.run = l.slice(4); else if (l.startsWith("free=")) k.free = Number(l.slice(5));
        else if (l.startsWith("boot=")) { const b = l.slice(5).trim().split(/\s+/).map(Number); k.bootSize = b[0]; k.bootUsed = b[1] }
        else if (l.startsWith("k|")) { const f = l.split("|"); k.list.push({ name: f[1], inst: f[2] === "1", ver: f[3], size: f[4] }) }
      }
      const ord = ["linux", "linux-zen", "linux-lts", "linux-hardened", "linux-rt", "linux-rt-lts", "linux-cachyos", "linux-cachyos-bore-lto", "linux-cachyos-bore", "linux-cachyos-eevdf-lto", "linux-cachyos-eevdf", "linux-cachyos-bmq-lto", "linux-cachyos-bmq", "linux-cachyos-server-lto", "linux-cachyos-server", "linux-cachyos-lts-lto", "linux-cachyos-lts", "linux-cachyos-hardened-lto", "linux-cachyos-hardened", "linux-cachyos-rt-bore-lto", "linux-cachyos-rt-bore", "linux-cachyos-deckify-lto", "linux-cachyos-deckify"]; k.list.sort((a, b) => ord.indexOf(a.name) - ord.indexOf(b.name))
      st.kern = k
    } }
  }
  property real kernProg: -1       // -1 = running, no numbers yet; 0..1 approximate share of the pacman steps
  property string kernText: ""
  property string kernVerb: ""
  function kernStep(raw) {
    const line = raw.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").trim(); if (!line) return;
    kernText = line.slice(0, 80);
    const m = line.match(/^\((\d+)\/(\d+)\)\s*(.*)/); if (!m || Number(m[2]) <= 0) return;
    const f = Number(m[1]) / Number(m[2]), w = m[3];
    // pacman prints no percentage without a terminal: the share is by phase (checks, install/remove, hooks); it never goes back
    const v = /checking|loading|resolving/.test(w) ? 0.1 + 0.25 * f : /installing|removing|upgrading/.test(w) ? 0.35 + 0.35 * f : 0.7 + 0.3 * f;
    kernProg = Math.max(kernProg, v);
  }
  Process {
    id: kernRun
    property string out: ""
    property string err: ""
    onStarted: { st.kernProg = -1; st.kernText = "Waiting for the password…" }
    stdout: SplitParser { onRead: line => { st.kernStep(line); if (line.startsWith("limine:")) kernRun.out = line.trim() } }
    stderr: StdioCollector { onStreamFinished: kernRun.err = this.text.trim().split("\n").pop() }
    onExited: code => { st.kernMsg = code === 0 ? (kernRun.out || "Done") : "Not done: " + (kernRun.err || "code " + code); st.kernBusy = ""; kernScan.running = true }
  }
  function kernAct(verb, name, extra) { if (kernBusy) return; kernBusy = name; kernVerb = verb; kernMsg = ""; kernRun.out = ""; kernRun.err = ""
    kernRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "kernel", verb, name].concat(extra ? [extra] : []); kernRun.running = true }
  property string kernArm: ""   // the fallback kernel waiting for the second click
  Timer { id: kernArmTimer; interval: 6000; onTriggered: st.kernArm = "" }
  Process {   // Limine's file is readable by root only: asked on demand, not on every open
    id: kernInfoRun
    command: ["pkexec", "/usr/local/libexec/lwts-priv", "kernel-info"]
    stdout: StdioCollector { onStreamFinished: { const m = this.text.match(/limine=(.*)/); st.kernMsg = m ? "Boot menu lists: " + (m[1] || "nothing") : "No answer" } }
    onExited: code => { if (code !== 0) st.kernMsg = "Cancelled or refused" }
  }
  function kernRows() {
    const k = kern, list = k.list || [], inst = list.filter(x => x.inst), avail = list.filter(x => !x.inst), rows = [];
    rows.push(header("Running"), info("Kernel", (k.run || "…")), ...(kernBusy ? [{ type: "progress", label: (kernVerb === "remove" ? "Removing " : "Installing ") + kernBusy, value: kernProg, text: kernText }] : []),
              { type: "progress", label: "Boot partition (/boot)", value: k.bootSize ? k.bootUsed / k.bootSize : -1,
                text: k.bootSize ? k.bootUsed + " of " + k.bootSize + " MB · " + k.free + " MB free" : "…" },
              { type: "action", label: "Boot menu (Limine)", desc: kernMsg || "Which kernels the menu lists (asks for the password). A kernel needs 150-200 MB on /boot; below 300 MB free installs are refused",
                buttons: [["Check", () => { kernMsg = "Checking…"; kernInfoRun.running = true }]] });
    rows.push(header("Installed"));
    for (const x of inst) {
      const keep = x.name === k.run || inst.length <= 1;
      if (x.name === "linux-lts" && !keep) {   // the fallback: removable, but only after an explicit warning and a second click
        rows.push({ type: "action", label: x.name, desc: kernBusy === x.name ? "Working…" : kernArm === x.name
                      ? "WARNING: it is your fallback. If the main kernel breaks, there will be nothing else to boot. Click again to remove it"
                      : x.ver + " · fallback kernel. Removing it needs a second click",
                    buttons: [[kernArm === x.name ? "Really remove" : "Remove…", () => {
                      if (kernArm === x.name) { kernArm = ""; kernAct("remove", x.name, "allow-fallback") } else { kernArm = x.name; kernArmTimer.restart() } }]] });
        continue;
      }
      rows.push(keep ? info(x.name, (x.name === k.run ? "In use" : "The only kernel") + " · " + x.ver)
                     : choice(x.name, kernBusy === x.name ? "Working…" : x.ver + " · " + x.size + ". Off removes it with its headers",
                              [["off", "Off"], ["on", "On"]], () => "on", v => { if (v === "off") kernAct("remove", x.name) }));
    }
    rows.push(header("Available"));
    for (const x of avail) rows.push(choice(x.name, kernBusy === x.name ? "Working… this can take a few minutes" : x.ver + " · " + x.size + ". On installs it with its headers",
                                            [["off", "Off"], ["on", "On"]], () => "off", v => { if (v === "on") kernAct("install", x.name) }));
    if (!avail.length) rows.push(info("Nothing more", "The connected repositories offer no other kernel"));
    if (kernMsg && kernMsg.indexOf("Boot menu") < 0) rows.push(info("Last result", kernMsg));
    return rows;
  }
  readonly property var coreServices: new Set(["dbus-broker.service", "dconf.service", "pipewire.service", "pipewire-pulse.service",
    "wireplumber.service", "gvfs-daemon.service", "gvfs-metadata.service", "gvfs-udisks2-volume-monitor.service",
    "at-spi-dbus-bus.service", "xdg-desktop-portal-gtk.service", "xdg-document-portal.service", "xdg-permission-store.service",
    "flatpak-portal.service", "flatpak-session-helper.service", "systemd-tmpfiles-setup.service", "daily-quests.service"])
  property var userServices: []
  Process {
    id: servicesScan
    command: ["bash", "-c", "systemctl --user list-units --type=service --no-pager --no-legend 2>/dev/null | awk '{print $1, $4}'"]
    stdout: StdioCollector { onStreamFinished: {
      st.userServices = this.text.trim().split("\n").filter(l => l.includes(".service"))
        .map(l => { const p = l.trim().split(/\s+/); return { name: p[0], state: p[1] || "", core: st.coreServices.has(p[0]) || p[0].startsWith("dbus-") || p[0] === "gamemoded.service" } });
    } }
  }
  function toggleService(name, running) { Quickshell.execDetached(["systemctl", "--user", running ? "stop" : "start", name]); servicesTimer.restart() }
  Timer { id: servicesTimer; interval: 1000; onTriggered: servicesScan.running = true }
  property bool svcOpen: false
  function serviceRows() {   // folded: 20+ lines of service names are noise; searching opens it
    const open = svcOpen || filter !== "", running = userServices.filter(x => x.state === "running").length;
    const rows = [{ type: "action", label: "User services", desc: running + " running of " + userServices.length, buttons: [[open ? "Hide" : "Show", () => { svcOpen = !svcOpen }]] }];
    if (open) for (const s of userServices) rows.push(s.core
      ? info(s.name.replace(".service", ""), "[System] " + s.state)
      : ({ type: "action", label: s.name.replace(".service", ""), desc: s.state,
           buttons: [[s.state === "running" ? "Stop" : "Start", () => toggleService(s.name, s.state === "running")]] }));
    return rows;
  }

  property string swappiness: ""
  Process { id: swapScan; command: ["cat", "/proc/sys/vm/swappiness"]
            stdout: StdioCollector { onStreamFinished: { st.swappiness = this.text.trim() } } }
  function cleanupNow() { cleanupRun.running = true }
  Process {
    id: cleanupRun
    command: ["alacritty", "-e", "sh", "-c", "sudo pacman -Sc; command -v flatpak >/dev/null && flatpak uninstall --unused -y; rm -rf \"$HOME/.cache/thumbnails\"/*; echo; read -p 'Press Enter to close' x"]
    onExited: updatesScan.running = true
  }
  function backupSettings() { Quickshell.execDetached(["bash", "-c",
    'cp "$HOME/.config/themes/settings.toml" "$HOME/.config/themes/settings.toml.backup-$(date +%Y%m%d-%H%M%S)"']) }
  function restoreSettings() { Quickshell.execDetached(["bash", "-c",
    'f=$(ls -t "$HOME"/.config/themes/settings.toml.backup-* 2>/dev/null | head -1); [ -n "$f" ] && cp "$f" "$HOME/.config/themes/settings.toml"']) }

  function vpnRows() {   // one row per NetworkManager VPN / WireGuard connection (nmcli, real; none are configured yet)
    return vpnConns.map(c => ({ type: "action", label: c.name, desc: c.active ? "Connected" : "Disconnected",
      buttons: [[c.active ? "Disconnect" : "Connect", () => { Quickshell.execDetached(["nmcli", "connection", c.active ? "down" : "up", c.name]); vpnRefresh.running = true }]] }));
  }
  property string wifiJoin: ""   // the secured network whose password is being typed
  function wifiRows() {   // Quickshell.Networking: nearby networks by signal, saved ones get Forget; a new secured one asks for the password under it
    const nets = wifiDev && wifiDev.networks ? wifiDev.networks.values.slice() : [];
    nets.sort((a, b) => (b.connected - a.connected) || ((b.signalStrength || 0) - (a.signalStrength || 0)));
    const out = [];
    for (const n of nets.filter(n => n.name)) {
      const open = n.security === WifiSecurityType.Open;
      const btns = [[n.connected ? "Disconnect" : "Connect", () => n.connected ? n.disconnect() : n.connect()]];
      if (n.known) btns.push(["Forget", () => n.forget()]);
      out.push({ type: "action", label: n.name,
        desc: (n.connected ? "Connected · " : n.known ? "Saved · " : "") + (open ? "Open" : "Secured") + " · " + Math.round((n.signalStrength || 0) * 100) + "%",
        buttons: (open || n.known || n.connected) ? btns : [[wifiJoin === n.name ? "Cancel" : "Join", () => { wifiJoin = wifiJoin === n.name ? "" : n.name }]] });
      if (wifiJoin === n.name && !open && !n.known && !n.connected)
        out.push(input("Password for " + n.name, "8 or more characters; Enter joins", () => "", v => { Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", n.name, "password", v, "ifname", wifiDev.name]); wifiJoin = "" },
                       { secret: true, placeholder: "password", validate: t => t.length < 8 ? "at least 8 characters" : "" }));
    }
    return out;
  }
  // DNS: presets written into the active connection (nmcli); "Auto" gives the choice back to the router
  readonly property var dnsPresets: [["auto", "Automatic (router)", ""], ["cloudflare", "Cloudflare 1.1.1.1", "1.1.1.1 1.0.0.1"], ["google", "Google 8.8.8.8", "8.8.8.8 8.8.4.4"],
                                     ["quad9", "Quad9 9.9.9.9", "9.9.9.9 149.112.112.112"], ["adguard", "AdGuard (blocks ads)", "94.140.14.14 94.140.15.15"]]
  property string netMsg: ""
  function setDns(id, servers) {
    dnsRun.command = ["bash", "-c", 'c=$(nmcli -t -f NAME,TYPE connection show --active | grep -E ":(802-3-ethernet|802-11-wireless)$" | head -1 | cut -d: -f1); [ -n "$c" ] || exit 3; '
      + (servers ? 'nmcli connection modify "$c" ipv4.dns "' + servers + '" ipv4.ignore-auto-dns yes' : 'nmcli connection modify "$c" ipv4.dns "" ipv4.ignore-auto-dns no')
      + ' && nmcli connection up "$c" >/dev/null']; dnsRun.preset = id; dnsRun.running = true
  }
  Process { id: dnsRun; property string preset: ""
            onExited: code => { st.netMsg = code === 0 ? "" : "Could not change DNS (is a connection active?)"; if (code === 0) Prefs.set("dns_preset", preset) } }
  Process { id: pingRun; command: ["bash", "-c", 'ping -c 3 -W 2 1.1.1.1 | tail -1; getent hosts example.com >/dev/null && echo "names: ok" || echo "names: failed"']
            stdout: StdioCollector { onStreamFinished: st.pingOut = this.text.trim().split("\n").join(" · ") } }
  property string pingOut: ""

  // ---- active connection profile (nmcli): real values, edits are a draft until Apply (a wrong static IP must not cut the link by itself)
  property var np: ({})        // id auto metered m a g d v6 mtu mac
  property var nd: ({})        // unsaved IP / DNS edits: m a g d
  property string npMsg: ""
  readonly property string netDev: wired && wired.connected ? wired.name : wifiDev && wifiDev.connected ? wifiDev.name : ""
  readonly property string mtuKey: wired && wired.connected ? "802-3-ethernet" : "802-11-wireless"
  function ndv(k) { return nd[k] !== undefined ? nd[k] : (np[k] !== undefined ? np[k] : "") }
  function ndSet(k, v) { nd = Object.assign({}, nd, { [k]: v }) }
  function npLoad() {
    if (!netDev || npRead.running) return;
    npRead.command = ["bash", "-c", 'c=$(nmcli -g GENERAL.CONNECTION device show "$1"); echo "$c"; nmcli -g connection.autoconnect,connection.metered,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,ipv6.method,"$2".mtu,"$2".cloned-mac-address connection show "$c"', "_", netDev, mtuKey]; npRead.running = true
  }
  Process {
    id: npRead
    stdout: StdioCollector { onStreamFinished: {
      const l = text.split("\n").map(x => x.replace(/\\:/g, ":").trim());
      st.np = { id: l[0], auto: l[1] !== "no", metered: l[2] || "unknown", m: l[3] === "manual" ? "manual" : "auto", a: (l[4] || "").split(",")[0], g: l[5] || "",
                d: (l[6] || "").split(",").filter(x => x).join(" "), v6: l[8] === "disabled" || l[8] === "ignore" ? "disabled" : "auto", mtu: !l[9] || l[9] === "auto" ? "0" : l[9], mac: l[10] || "" };
    } }
  }
  Process { id: npMod; onExited: code => { st.npMsg = code === 0 ? "" : "NetworkManager refused it - check the values"; if (code === 0) { st.nd = ({}); st.npLoad() } } }
  function npRun(args) {   // modify the profile and reapply it live; args = "prop value prop value ..."
    if (!np.id || !netDev || npMod.running) return;
    npMod.command = ["bash", "-c", 'c="$1"; d="$2"; shift 2; nmcli connection modify "$c" "$@" && nmcli device reapply "$d"', "_", np.id, netDev].concat(args); npMod.running = true
  }
  function dnsList(t) { return String(t).split(/[\s,]+/).filter(x => x) }
  function okIp(x) { return /^\d{1,3}(\.\d{1,3}){3}$/.test(x) && x.split(".").every(n => Number(n) <= 255) }
  function npApply() {
    const man = ndv("m") === "manual", dl = dnsList(ndv("d"));
    if (man && !(/^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/.test(ndv("a")) && okIp(ndv("a").split("/")[0]) && okIp(ndv("g")))) { npMsg = "Manual needs an address like 192.168.1.50/24 and a gateway"; return }
    if (dl.length > 3 || !dl.every(okIp)) { npMsg = "DNS: up to 3 IPv4 addresses"; return }
    npRun(["ipv4.method", man ? "manual" : "auto", "ipv4.addresses", man ? ndv("a") : "", "ipv4.gateway", man ? ndv("g") : "",
           "ipv4.dns", dl.join(","), "ipv4.ignore-auto-dns", dl.length ? "yes" : "no"])
  }
  readonly property bool npDirty: Object.keys(nd).some(k => nd[k] !== np[k])
  onNetDevChanged: { nd = ({}); npLoad() }
  property var vpnConns: []
  Process {   // one-shot list of vpn/wireguard connections + which is active (re-run after a connect/disconnect click)
    id: vpnRefresh
    command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
    stdout: StdioCollector { onStreamFinished: {
      st.vpnConns = this.text.trim().split("\n").filter(l => l).map(l => l.split(":"))
                      .filter(p => p[1] === "vpn" || p[1] === "wireguard").map(p => ({ name: p[0], active: p[2] === "yes" }));
    } }
  }

  // categories like macOS / GNOME: sidebar left, the page right; a header row starts a new group (card)
  // ---- monitor map (settings_spec 9.1): logical rects from niri outputs; a drop snaps to the nearest neighbour side
  property int monSel: 0
  property string lastKey: ""     // 6.1 key tester: the last combo pressed while its row is focused
  function monLogical() {
    return System.monitors.map(m => { const rot = m.transform % 2 === 1;
      return { name: m.name, x: m.x, y: m.y, w: Math.round((rot ? m.height : m.width) / m.scale), h: Math.round((rot ? m.width : m.height) / m.scale) } });
  }
  function monDrop(i, x, y, tol) {   // tol: snap distance in monitor px (= ~24 px on the map)
    const ms = monLogical(), me = ms[i]; let best = null, bd = 1e9;
    if (me && Math.hypot(x - me.x, y - me.y) > tol / 4) for (let j = 0; j < ms.length; j++) {
      if (j === i) continue; const o = ms[j];
      for (const side of ["right", "left", "up", "down"]) {
        const horiz = side === "right" || side === "left";
        const cx0 = side === "right" ? o.x + o.w : side === "left" ? o.x - me.w : x;
        const cy0 = side === "up" ? o.y - me.h : side === "down" ? o.y + o.h : y;
        // the free axis: align start / centre / end with the neighbour when close, else keep where dropped (still touching)
        const free = horiz ? cy0 : cx0, os = horiz ? o.y : o.x, ol = horiz ? o.h : o.w, ml = horiz ? me.h : me.w;
        let f = Math.max(os - ml + 1, Math.min(os + ol - 1, free));
        for (const a of [os, os + (ol - ml) / 2, os + ol - ml]) if (Math.abs(f - a) < tol) { f = a; break }
        const cx = horiz ? cx0 : f, cy = horiz ? f : cy0;
        const d = Math.hypot(cx - x, cy - y); if (d < bd) { bd = d; best = [Math.round(cx), Math.round(cy)] }
      }
    }
    if (best && (best[0] !== me.x || best[1] !== me.y)) Look.setDisplay(me.name, "position", best[0] + "x" + best[1]);
    System.refresh();   // re-creates the rects at the real positions (a drag breaks their bindings)
  }
  function monMove(side) {   // keyboard: attach the selected monitor to that side of the other one
    const ms = monLogical(), me = ms[monSel], o = ms.find((m, j) => j !== monSel);
    if (!me || !o) return;
    const p = side === "left" ? [o.x - me.w, o.y] : side === "right" ? [o.x + o.w, o.y] : side === "up" ? [o.x, o.y - me.h] : [o.x, o.y + o.h];
    if (p[0] !== me.x || p[1] !== me.y) Look.setDisplay(me.name, "position", p[0] + "x" + p[1]);
  }

  property string dspSel: ""   // Displays: the monitor whose controls are shown (spec: one at a time)
  function displayRows() {
    const all = System.monitors, one = all.find(x => x.name === dspSel) || all[0];
    return [].concat(...(one ? [one] : []).map(m => [
      all.length > 1 ? choice("Monitor", "", all.map(x => [x.name, x.name]), () => m.name, v => st.dspSel = v) : header(m.name),
      cycle("Resolution", "Reverts in 12 s unless kept", m.modes.map(x => [x, x.replace("Hz", " Hz")]),
            () => m.mode, v => Look.setDisplay(m.name, "mode", v)),
      choice("Scale", "", [[1, "100%"], [1.25, "125%"], [1.5, "150%"], [2, "200%"]],
             () => Number(m.scale), v => Look.setDisplay(m.name, "scale", v)),
      choice("Rotation", "Reverts in 12 s unless kept", [[0, "Normal"], [1, "90°"], [2, "180°"], [3, "270°"]],
             () => Number(m.transform), v => Look.setDisplay(m.name, "transform", v)),
      choice("Adaptive sync (VRR)", "On demand = games only; reverts in 12 s unless kept", [[0, "Off"], [1, "Always"], [2, "On demand"]],
             () => Look.vrrMode(m), v => Look.setDisplay(m.name, "vrr", v)),
      cycle("Colour depth", "Needs a monitor and cable that support it; reverts in 12 s unless kept", [["", "Driver default"], ["8", "8 bit"], ["10", "10 bit"]],
            () => String(Prefs.get("dsp_" + m.name.replace(/-/g, "_") + "_bitdepth", "")), v => Look.setDisplay(m.name, "bitdepth", v)),
      cycle("Colour space", "", [["", "Driver default"], ["srgb", "sRGB"], ["auto", "Auto"], ["wide", "Wide (BT.2020)"], ["dcip3", "DCI-P3"], ["adobe", "Adobe RGB"], ["edid", "From the monitor (EDID)"]],
            () => String(Prefs.get("dsp_" + m.name.replace(/-/g, "_") + "_cm", "")), v => Look.setDisplay(m.name, "cm", v)),
      cycle("Mirror of", "Reverts in 12 s unless kept", [["", "No (extend)"]].concat(System.monitors.filter(o => o.name !== m.name).map(o => [o.name, o.name])),
            () => String(Prefs.get("dsp_" + m.name.replace(/-/g, "_") + "_mirror", "")), v => Look.setDisplay(m.name, "mirror", v)),
    ]));
  }
  // ---- pinned (settings_spec 1.1): a row with a `pin` id is in the registry; settings.toml `pinned` lists the shown ones.
  // The Pinned page reuses the very same row objects - no second copy of any setting. Unknown ids are skipped.
  readonly property var defaultPins: ["sys_updates", "sys_cleanup", "power_profile"]
  readonly property var pinned: Prefs.get("pinned", defaultPins)
  readonly property var registry: { const m = {}; for (const s of body) for (const r of s.rows) if (r.pin) m[r.pin] = r; return m }
  function isPinned(id) { return pinned.indexOf(id) >= 0 }
  function togglePin(id) { toggleIn("pinned", id, defaultPins) }
  readonly property var pinnedRows: pinned.map(id => registry[id]).filter(r => !!r)
  readonly property var sections: [{ id: "pinned", icon: "push-pin", label: "Pinned",
                                     rows: pinnedRows.length ? pinnedRows : [header("Nothing pinned yet")] }].concat(body)

  // every real setting gets a pin id (settings_spec 1.1: a pin on each card); explicit `pin:` ids (the defaults) are kept
  function expandMulti(r, afterHeader) {   // a chip wall -> one switch row per option (Windows / macOS lists)
    return (afterHeader ? [] : [header(r.label)]).concat(r.desc ? [info(r.desc, "")] : [],
      r.options.map(o => choice(o[1], "", [["on", "On"], ["off", "Off"]],
                 () => r.isOn(o[0]) ? "on" : "off", v => { if ((v === "on") !== !!r.isOn(o[0])) r.toggle(o[0]) })))
  }
  function withPins(secs) {
    for (const sec of secs) sec.rows = [].concat(...sec.rows.map((r, i) => r.type === "multi" ? expandMulti(r, i > 0 && sec.rows[i - 1].type === "header") : [r]));
    const slug = t => String(t || "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
    for (const sec of secs) {
      let tabId = "", seen = {};
      for (const r of sec.rows) {
        if (r.type === "tab") { tabId = slug(r.label); continue }
        if (r.type === "header" || r.type === "info" || !r.label || r.pin) continue;
        let id = sec.id + "." + tabId + "." + slug(r.label); const n = seen[id] = (seen[id] || 0) + 1;
        r.pin = n > 1 ? id + "_" + n : id;
      }
    }
    return secs;
  }
  readonly property var body: withPins(Modules.extend(rawBody))
  // one binding per section: a scan result rebuilds only its own section, not all of them (each full rebuild cost 13-22 ms = dropped frames at 60 Hz)
  // ==== Settings v4 tree: one binding per section, as before ====
  // hardware visibility (spec principle 4): touchpad / TrackPoint rows only when the kernel lists one
  property bool hasTouchpad: false
  property bool hasTrackpoint: false
  Process {
    running: true
    command: ["bash", "-c", "n=$(grep -i '^N: Name=' /proc/bus/input/devices); echo \"$n\" | grep -qi 'touchpad' && echo tp; echo \"$n\" | grep -qiE 'trackpoint|TPPS/2' && echo pt; true"]
    stdout: StdioCollector { onStreamFinished: { const t = this.text; st.hasTouchpad = t.indexOf("tp") >= 0; st.hasTrackpoint = t.indexOf("pt") >= 0 } }
  }
  // Storage -> Apps: installed size per launcher app (owning pacman package or Flatpak app), read once per visit
  property var appSizes: ({})   // desktop id -> { pkg, bytes }
  Process {
    id: appSizeScan
    command: ["bash", "-c", "for d in /usr/share/applications \"$HOME\"/.local/share/applications; do for f in \"$d\"/*.desktop; do [ -f \"$f\" ] || continue; "
      + "p=$(pacman -Qqo \"$f\" 2>/dev/null) || continue; printf 'F\\t%s\\t%s\\n' \"${f##*/}\" \"$p\"; done; done; "
      + "pacman -Qi 2>/dev/null | awk -F': ' '/^Name/ {n=$2} /^Installed Size/ {print \"S\\t\" n \"\\t\" $2}'; "
      + "command -v flatpak >/dev/null && flatpak list --app --columns=application,size 2>/dev/null | awk -F'\\t' '{print \"P\\t\" $1 \".desktop\\t\" $2}'; true"]
    stdout: StdioCollector { onStreamFinished: {
      const unit = s => { const m = String(s).replace(",", ".").match(/([\d.]+)\s*([KMGT]?i?B|[kMGT]B)/i); if (!m) return 0
                          const k = { b: 1, kib: 1024, kb: 1000, mib: 1048576, mb: 1e6, gib: 1073741824, gb: 1e9, tib: 1099511627776, tb: 1e12 }[m[2].toLowerCase()] || 1; return Number(m[1]) * k }
      const own = {}, size = {}, out = {};
      for (const l of this.text.split("\n")) { const p = l.split("\t"); if (p[0] === "F") own[p[1]] = p[2]; else if (p[0] === "S") size[p[1]] = unit(p[2]); else if (p[0] === "P") out[p[1]] = { pkg: "flatpak", bytes: unit(p[2]) } }
      for (const id in own) out[id] = { pkg: own[id], bytes: size[own[id]] || 0 };
      st.appSizes = out;
    } }
  }
  function human(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : b >= 1048576 ? Math.round(b / 1048576) + " MB" : b > 0 ? Math.max(1, Math.round(b / 1024)) + " KB" : "" }
  function storageAppRows() {
    const sz = id => (appSizes[id] || {}).bytes || 0;
    return appRows.slice().sort((a, b) => sz(b[0]) - sz(a[0]) || a[1].localeCompare(b[1])).map(([id, name]) => {
      const s = appSizes[id];
      return { type: "action", label: name, desc: s ? (s.pkg === "flatpak" ? "Flatpak" : s.pkg) + (human(s.bytes) ? " · " + human(s.bytes) : "") : id,
               buttons: [["Uninstall", () => manageApp(id, "uninstall")], ["Reset data", () => manageApp(id, "reset")]] };
    });
  }
  readonly property bool storageOpen: !!sections[section] && sections[section].id === "storage" && filter === ""
  onStorageOpenChanged: if (storageOpen && !Object.keys(appSizes).length) appSizeScan.running = true
  // Appearance -> Shell: one Materials row instead of transparency + blur knobs (spec: Off / Acrylic / Glass)
  function setMaterial(v) { const t = ({ off: "solid", acrylic: "soft", glass: "glass" })[v]; Look.setHypr({ transparency: t, opacity: ({ glass: 0.75, soft: 0.88, solid: 1 })[t] }) }
  readonly property string material: ({ solid: "off", soft: "acrylic", glass: "glass" })[Prefs.transparency] || "acrylic"

  readonly property var sec_wifi: wifiDev ? (
    { id: "wifi", icon: "wifi-high", label: "Wi-Fi", rows: [
      choice("Wi-Fi", "", [["off", "Off"], ["on", "On"]], () => Networking.wifiEnabled ? "on" : "off", v => Networking.wifiEnabled = v === "on"),
      info("Current network", (() => { const n = wifiDev.networks ? wifiDev.networks.values.find(n => n.connected) : null;
                                         return n ? n.name + " · " + Math.round((n.signalStrength || 0) * 100) + "%" : "Not connected" })()),
      header("Hotspot"),
      input("Hotspot name", "", () => Prefs.get("hotspot_ssid", "LWTS"), v => Prefs.set("hotspot_ssid", v.trim()),
            { validate: t => t.trim().length < 1 || t.length > 32 ? "1-32 characters" : "" }),
      input("Hotspot password", "8 or more characters", () => Prefs.get("hotspot_pass", ""), v => Prefs.set("hotspot_pass", v),
            { secret: true, placeholder: "password", validate: t => t.length < 8 || t.length > 63 ? "8-63 characters" : "" }),
      { type: "action", label: "Hotspot", desc: Prefs.get("hotspot_pass", "") ? "Shares this connection as Wi-Fi" : "Set a password first",
        buttons: [["Start", () => { if (Prefs.get("hotspot_pass", "")) Quickshell.execDetached(["nmcli", "dev", "wifi", "hotspot", "ifname", wifiDev.name, "ssid", Prefs.get("hotspot_ssid", "LWTS"), "password", Prefs.get("hotspot_pass", "")]) }],
                  ["Stop", () => Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"])]] },
      header("Networks")].concat(wifiRows()) }
  ) : null
  readonly property var sec_bluetooth: Bluetooth.defaultAdapter ? ({ id: "bluetooth", icon: "bluetooth", label: "Bluetooth", rows: btRows() }) : null
  readonly property var sec_network: (
    { id: "network", icon: "network", label: "Network", rows: [].concat(
      [tab("Connection"),
       info("Status", wired && wired.connected ? "Connected by cable" + (Number(String(NetInfo.info.speed).replace(/\D/g, "")) > 0 ? " (" + NetInfo.info.speed + ")" : "") : wifiDev && wifiDev.connected ? "Connected over Wi-Fi" : wired ? "Cable unplugged" : "Offline"),
       info("Address", (NetInfo.info.ip || "—") + (NetInfo.info.gw ? "  ·  gateway " + NetInfo.info.gw : "")),
       ...(wired && wired.connected && /^(10|100)\b/.test(String(NetInfo.info.speed || "")) ? [info("Slow link", "Only " + NetInfo.info.speed + " - a gigabit port normally shows 1000. Check the cable and the plug")] : []),
       info("Profile", np.id || "—"),
       choice("Flight mode", "Wi-Fi, Bluetooth and WWAN off", [["off", "Off"], ["on", "On"]],
              () => Tiles.all.flight.on() ? "on" : "off", v => { if ((v === "on") !== Tiles.all.flight.on()) Tiles.all.flight.act() }),
       choice("Auto-connect", "", [["on", "On"], ["off", "Off"]], () => np.auto ? "on" : "off", v => npRun(["connection.autoconnect", v === "on" ? "yes" : "no"])),
       choice("Metered", "Limits background downloads on apps that respect it", [["unknown", "Auto"], ["yes", "Metered"], ["no", "Unmetered"]], () => np.metered || "unknown", v => npRun(["connection.metered", v])),
       header("Advanced"),
       input("MTU", "0 = automatic", () => String(np.mtu || "0"), v => npRun([mtuKey + ".mtu", v.trim() || "0"]), { validate: t => /^\d+$/.test(t.trim()) && (Number(t) === 0 || (Number(t) >= 576 && Number(t) <= 9000)) ? "" : "0 or 576-9000" }),
       input("MAC address", "Empty = the real one; random / stable also work", () => np.mac || "", v => npRun([mtuKey + ".cloned-mac-address", v.trim()]),
             { validate: t => t.trim() === "" || /^(random|stable|preserve|permanent)$/.test(t.trim()) || /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(t.trim()) ? "" : "aa:bb:cc:dd:ee:ff" }),
       { type: "action", label: "Connection", desc: pingOut || "Reconnect re-reads everything; Test pings 1.1.1.1 and resolves a name",
         buttons: [["Reconnect", () => { if (np.id) Quickshell.execDetached(["bash", "-c", 'nmcli connection down "$1"; nmcli connection up "$1"', "_", np.id]) }],
                   ["Test", () => { pingOut = "Testing…"; pingRun.running = true }]] },
       tab("IP & DNS"),
       choice("IPv4", "", [["auto", "Automatic (DHCP)"], ["manual", "Manual"]], () => ndv("m") || "auto", v => ndSet("m", v)),
       ...(ndv("m") === "manual" ? [
         input("IP address", "With the prefix, e.g. 192.168.1.50/24", () => ndv("a"), v => ndSet("a", v.trim()), { validate: t => /^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/.test(t.trim()) ? "" : "192.168.1.50/24" }),
         input("Gateway", "", () => ndv("g"), v => ndSet("g", v.trim()), { validate: t => okIp(t.trim()) ? "" : "192.168.1.1" })] : []),
       cycle("DNS preset", "", dnsPresets.map(d => [d[0], d[1]]).concat([["custom", "Custom"]]),
             () => { const t = dnsList(ndv("d")).join(" "); const m = dnsPresets.find(d => d[2] === t); return m ? m[0] : t === "" ? "auto" : "custom" },
             v => { if (v !== "custom") ndSet("d", dnsPresets.find(d => d[0] === v)[2]) }),
       input("DNS servers", "Up to 3 IPv4 addresses, empty = from the router", () => ndv("d"), v => ndSet("d", dnsList(v).join(" ")), { validate: t => dnsList(t).length <= 3 && dnsList(t).every(okIp) ? "" : "e.g. 1.1.1.1 8.8.8.8" }),
       choice("IPv6", "", [["auto", "Automatic"], ["disabled", "Off"]], () => np.v6 || "auto", v => npRun(["ipv6.method", v])),
       { type: "action", label: "Apply", desc: npMsg || (npDirty ? "Unsaved changes: nothing is touched until Apply" : "Saved"),
         buttons: [["Apply", () => npApply()], ["Discard", () => { nd = ({}); npMsg = "" }]] },
       tab("VPN"), header("VPN")],
      vpnRows().length ? vpnRows() : [info("Profiles", "None configured (nmcli)")],
      modemPresent ? [tab("Mobile"), header("Mobile data (WWAN)"), info("Modem", "Detected — full controls not built yet (settings_gaps.md)")] : []
    ) }
  )
  readonly property var sec_sound: (
    { id: "sound", icon: "speaker-high", label: "Sound", rows: [
      tab("Output"),
      ...deviceRows(true),
      header("Volume"),
      slider("Volume", "", Prefs.get("audio_overdrive", false) ? [0, 25, 50, 75, 100, 125, 150] : [0, 25, 50, 75, 100], "%",
             () => Math.round(Audio.volume * 100), v => Audio.setVolume(v / 100)),
      choice("Mute", "", [["off", "Off"], ["on", "On"]], () => Audio.muted ? "on" : "off", v => { if ((v === "on") !== Audio.muted) Audio.toggleMute() }),
      slider("Balance", "", [-50, -25, 0, 25, 50], "%", audioBalance, setAudioBalance),
      choice("Overdrive", "Up to 150%", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("audio_overdrive", false) ? "on" : "off", v => Prefs.set("audio_overdrive", v === "on")),
      { type: "action", label: "Test sound", desc: "Plays a short tone through the current output", buttons:
        [["Test", () => Quickshell.execDetached(["pw-play", "--target", Audio.sink ? Audio.sink.name : "@DEFAULT_SINK@",
                                                  Sounds.lib + "/test-tone.oga"])]] },
      tab("Input"),
      ...deviceRows(false),
      header("Microphone"),
      { type: "meter", label: "Mic level", desc: "Live while this page is open" },
      slider("Sensitivity", "", [0, 25, 50, 75, 100], "%",
             () => Audio.source && Audio.source.audio ? Math.round(Audio.source.audio.volume * 100) : 0,
             v => { if (Audio.source && Audio.source.audio) Audio.source.audio.volume = v / 100 }),
      choice("Listen to this device", "Mic through the speakers; use headphones", [["off", "Off"], ["on", "On"]],
             () => listenId ? "on" : "off", v => listenSet(v === "on")),
      choice("Mute mic", "", [["off", "Off"], ["on", "On"]], () => Audio.micMuted ? "on" : "off", v => { if ((v === "on") !== Audio.micMuted) Audio.toggleMic() }),
      tab("System sounds"),
      header("Sounds"),
      choice("Event sounds", "", [["on", "On"], ["off", "Off"]],
             () => Sounds.on ? "on" : "off", v => { Prefs.set("sound_theme", v === "on" ? "lwts" : "off"); Qt.callLater(() => Sounds.play("message-new-instant", true)) }),
      choice("Pack", "", [["keys", "Keys"], ["glass", "Glass"], ["retro", "Retro"]],
             () => Sounds.pack, v => { Prefs.set("sound_pack", v); Qt.callLater(() => Sounds.play("message-new-instant", true)) }),
      slider("Volume", "", [20, 40, 60, 80, 100], "%",
             () => Sounds.volume, v => { Prefs.set("sound_volume", v); Sounds.play("message-new-instant", true) }),
    ] }
  )
  readonly property var sec_notifications: (
    { id: "notifications", icon: "bell", label: "Notifications", rows: [
      tab("Notifications"),
      header("Mode"),
      choice("Mode", "", [["silence", "Full silence"], ["dot", "Dot only"], ["both", "Dot + Pop-ups"]],
             () => Notifs.mode, v => Prefs.set("notif_mode", v)),
      choice("Quiet while Lite mode is on", "Pop-ups stay silent during games and Lite", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("notif_quiet_in_game", true) ? "on" : "off", v => Prefs.set("notif_quiet_in_game", v === "on")),
      header("Pop-ups"),
      choice("Timeout", "", [[3000, "3 s"], [5000, "5 s"], [8000, "8 s"], [12000, "12 s"]],
             () => Number(Prefs.get("notif_timeout", 5000)), v => Prefs.set("notif_timeout", v)),
      choice("Sound", "", [["off", "Off"], ["all", "Normal"], ["critical", "Urgent only"]],
             () => Prefs.get("notif_sound", "off"), v => { Prefs.set("notif_sound", v); Sounds.play("message-new-instant", true) }),
      header("History"),
      choice("Storage limit", "", [[30, "30"], [50, "50"], [100, "100"]],
             () => Number(Prefs.get("notif_limit", 50)), v => Prefs.set("notif_limit", v)),
      { type: "action", label: "Clear history", desc: "", buttons: [["Clear all", () => Notifs.clear()]] },
    ] }
  )
  readonly property var sec_appearance: (
    { id: "appearance", icon: "palette", label: "Appearance", rows: [
      tab("Look"),
      header("Wallpaper"),
      { type: "picker", kind: "wallpaper", label: "Wallpaper", desc: "", pin: "appearance.global.wallpaper",
        value: () => Look.currentWall.split("/").pop() },
      choice("Wallpaper tint", "", [["off", "Off"], ["soft", "Soft"], ["full", "Full"]],
             () => Prefs.get("recolor", "off"), v => Look.setRecolor(v)),
      choice("Wallpaper dimming", "", [["off", "Off"], ["light", "Low"], ["strong", "High"]],
             () => Prefs.get("wall_dim", "off"), v => Look.setDim(v)),
      header("Theme"),
      { type: "picker", kind: "palette", label: "Palette", desc: "", pin: "appearance.global.palette",
        value: () => (Look.palettes.find(p => p.id === Look.currentPalette) || { label: Look.currentPalette }).label },
      choice("Mode", "", [["dark", "Dark"], ["light", "Light"]],
             () => Session.dark ? "dark" : "light", v => { if ((v === "dark") !== Session.dark) Session.toggleDark() }),
      choice("Schedule", "", [["manual", "Manual"], ["sun", "Sunset"], ["time", "Own time"]],
             () => Prefs.get("darkmode_mode", "manual"), v => Look.oldSet("darkmode_mode", v)),
      header("Windows"),
      choice("Gaps", "Space between windows", [["none", "None"], ["compact", "Compact"], ["spacious", "Spacious"]],
             () => Prefs.gapPreset, v => { Prefs.set("gap_preset", v); NiriConf.apply() }),
      choice("Corners", "Window and panel corners", [["square", "Square"], ["soft", "Soft"]],
             () => Prefs.roundingPreset === "square" ? "square" : "soft", v => { Prefs.set("rounding_preset", v); NiriConf.apply() }),
      header("Materials"),
      choice("Materials", "", [["off", "Off"], ["acrylic", "Acrylic"], ["glass", "Glass"]], () => material, v => setMaterial(v)),
      header("Cursor"),
      choice("Cursor size", "", [["20", "Small"], ["24", "Normal"], ["32", "Large"]],
             () => String(Prefs.get("cursor_size", 24)), v => Look.oldSet("cursor_size", Number(v))),
      tab("Displays"), { type: "monmap", label: "Arrangement", desc: "" },
      choice("Primary monitor", "At 0×0 and carries the bar · reverts in 12 s unless kept", System.monitors.map(m => [m.name, m.name]),
             () => Prefs.get("primary_monitor", "") || (System.monitors.find(m => m.x === 0 && m.y === 0) || {}).name || "",
             v => Look.setPrimary(v)),
      ...displayRows(),   // Night light (module daynight) joins this tab: same tab label
      tab("Bars"),
      header("Top bar"),
      choice("Position", "", [["top", "Top"], ["bottom", "Bottom"]], () => Prefs.barPosition, v => Prefs.set("bar_position", v)),
      multi("Modules", "",
            [["hyprland/workspaces", "Workspaces"], ["mpris", "Media"], ["hyprland/window", "Window title"], ["hyprland/language", "Layout"]],
            id => Prefs.module(id), id => toggleIn("waybar_hidden", id, [])),
      choice("App icons", "", [["tint", "Mono"], ["orig", "Original"]],
             () => Prefs.get("tray_tint", true) ? "tint" : "orig", v => Prefs.set("tray_tint", v === "tint")),
      ...(Prefs.gapPreset === "none" ? [choice("Screen corners", "", [["square", "Off"], ["round", "Rounded"]],
             () => Prefs.get("bar_gap_rounded", false) ? "round" : "square", v => Prefs.set("bar_gap_rounded", v === "round"))] : []),
      header("Launcher"),
      choice("Tray in launcher", "The apps' tray icons on the POWER line", [["on", "On"], ["off", "Off"]],
             () => Tiles.lookOf("tray") === "off" ? "off" : "on", v => Tiles.setLook("tray", v === "on" ? "text" : "off")),
      ...[["light", "Brightness"], ["vol", "Sound"], ["mic", "Microphone"]].filter(b => b[0] !== "light" || Brightness.available)
        .map(b => choice(b[1] + " bar", b[0] === "vol" ? "The mixer button sits on this bar" : "", [["on", "On"], ["off", "Off"]],
               () => Prefs.get("qs_bars", ["light", "vol"]).includes(b[0]) ? "on" : "off",
               v => { const cur = Prefs.get("qs_bars", ["light", "vol"]).filter(x => x !== b[0]); Prefs.set("qs_bars", v === "on" ? cur.concat([b[0]]) : cur) })),
      { type: "tab", label: "Quick settings", grid: true },   // QsConstructor: custom full-width renderer, no rows
      tab("Lock screen"),
      choice("Clock size", "", [["small", "Small"], ["normal", "Normal"], ["large", "Large"]],
             () => Prefs.get("lock_scale", "normal"), v => lockSet("lock_scale", v)),
      choice("Clock format", "", [["24", "24-hour"], ["12", "12-hour"]],
             () => Prefs.get("lock_hour12", false) === true ? "12" : "24", v => lockSet("lock_hour12", v === "12")),
      choice("Field width", "", [["narrow", "Narrow"], ["normal", "Normal"], ["wide", "Wide"]],
             () => Prefs.get("lock_input", "normal"), v => lockSet("lock_input", v)),
      choice("Keyboard layout", "", [["on", "On"], ["off", "Off"]],
             () => Prefs.get("lock_layout", true) ? "on" : "off", v => lockSet("lock_layout", v === "on")),
      choice("Battery", "", [["on", "On"], ["off", "Off"]],
             () => Prefs.get("lock_battery", true) ? "on" : "off", v => lockSet("lock_battery", v === "on")),
      choice("Media card", "While a player is running", [["on", "On"], ["off", "Off"]],
             () => Prefs.get("lock_media", true) === false ? "off" : "on", v => lockSet("lock_media", v === "on")),
      choice("Animation", "Opening, closing and fade speed", [["fast", "Fast"], ["normal", "Normal"], ["calm", "Calm"]],
             () => Prefs.get("lock_anim", "normal"), v => lockSet("lock_anim", v)),
      choice("Smooth return", "Fade the lock out over the windows after unlocking", [["on", "On"], ["off", "Off"]],
             () => Prefs.get("lock_veil", true) === false ? "off" : "on", v => lockSet("lock_veil", v === "on")),
    ] }
  )
  readonly property var sec_devices: (
    { id: "devices", icon: "keyboard", label: "Devices", rows: [].concat([
      tab("Keyboard"),
      header("Layouts"),
      ...kbLayoutRows(),
      ...(String(Prefs.get("kb_layout", "us,ua,ru")).split(",").length > 1 ? [cycle("Switch layout", "", kbSwitchOptions(),
             () => Prefs.get("kb_switch", "grp:alt_shift_toggle"), v => setKb("kb_switch", v))] : []),
      choice("Caps Lock", "", [["", "Normal"], ["caps:escape", "Escape"], ["caps:escape_shifted_capslock", "Escape (Shift+Caps = Caps)"], ["caps:super", "Super"], ["caps:ctrl_modifier", "Ctrl"]],
             () => Prefs.get("kb_caps", ""), v => setKb("kb_caps", v)),
      choice("Num Lock at start", "", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("kb_numlock", false) ? "on" : "off", v => Look.setInput({ kb_numlock: v === "on" })),
      header("Typing"),
      slider("Repeat delay", "", [150, 200, 250, 300, 400, 600], "ms",
             () => Number(Prefs.get("kb_repeat_delay", 250)), v => Look.setInput({ kb_repeat_delay: v })),
      slider("Repeat rate", "", [10, 25, 50, 75, 100], "/s",
             () => Number(Prefs.get("kb_repeat_rate", 50)), v => Look.setInput({ kb_repeat_rate: v })),
],
      [tab("Mouse"),
      header("Pointer"),
      Object.assign(slider("Sensitivity", "−1 slow · 0 default · +1 fast", Array.from({ length: 21 }, (_, i) => Math.round((-1 + i * 0.1) * 10) / 10), "",
             () => Number(Prefs.get("mouse_speed", 0)), v => Look.setInput({ mouse_speed: v })), { format: v => (v > 0 ? "+" : "") + Number(v).toFixed(1) }),
      choice("Acceleration", "", [["flat", "Flat"], ["adaptive", "Adaptive"]],
             () => Prefs.get("mouse_accel", "flat"), v => Look.setInput({ mouse_accel: v })),
      header("Scroll & buttons"),
      choice("Natural scroll", "", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("natural_scroll", false) ? "on" : "off", v => Look.setInput({ natural_scroll: v === "on" })),
      slider("Scroll speed", "", [0.5, 0.75, 1, 1.5, 2, 3], "×",
             () => Number(Prefs.get("scroll_factor", 1)), v => Look.setInput({ scroll_factor: v })),
      choice("Left-handed", "", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("left_handed", false) ? "on" : "off", v => Look.setInput({ left_handed: v === "on" }))],
      hasTouchpad ? [tab("Touchpad"), header("Pointer"),
        Object.assign(slider("Sensitivity", "−1 slow · 0 default · +1 fast", Array.from({ length: 21 }, (_, i) => Math.round((-1 + i * 0.1) * 10) / 10), "",
               () => Number(Prefs.get("tp_speed", 0)), v => Look.setInput({ tp_speed: v })), { format: v => (v > 0 ? "+" : "") + Number(v).toFixed(1) }),
        choice("Acceleration", "", [["adaptive", "Adaptive"], ["flat", "Flat"]],
               () => Prefs.get("tp_accel", "adaptive"), v => Look.setInput({ tp_accel: v })),
        header("Gestures"),
        choice("Tap to click", "", [["off", "Off"], ["on", "On"]],
               () => Prefs.get("tp_tap", true) ? "on" : "off", v => Look.setInput({ tp_tap: v === "on" })),
        choice("Natural scroll", "", [["off", "Off"], ["on", "On"]],
               () => Prefs.get("tp_natural", true) ? "on" : "off", v => Look.setInput({ tp_natural: v === "on" })),
        choice("Click method", "Clickfinger: 1 / 2 / 3 fingers = left / right / middle. Areas: the pad's corners", [["clickfinger", "Fingers"], ["areas", "Areas"]],
               () => Prefs.get("tp_click", "clickfinger"), v => Look.setInput({ tp_click: v })),
        header("While typing / with a mouse"),
        choice("Disable while typing", "", [["off", "Off"], ["on", "On"]],
               () => Prefs.get("tp_dwt", true) ? "on" : "off", v => Look.setInput({ tp_dwt: v === "on" })),
        choice("Off with an external mouse", "", [["off", "Off"], ["on", "On"]],
               () => Prefs.get("tp_off_with_mouse", false) ? "on" : "off", v => Look.setInput({ tp_off_with_mouse: v === "on" }))] : [],
      hasTrackpoint ? [tab("TrackPoint"), header("Pointer"),
        Object.assign(slider("Sensitivity", "−1 slow · 0 default · +1 fast", Array.from({ length: 21 }, (_, i) => Math.round((-1 + i * 0.1) * 10) / 10), "",
               () => Number(Prefs.get("pt_speed", 0)), v => Look.setInput({ pt_speed: v })), { format: v => (v > 0 ? "+" : "") + Number(v).toFixed(1) }),
        choice("Scroll with the middle button", "Hold the middle button and push the stick", [["off", "Off"], ["on", "On"]],
               () => Prefs.get("pt_middle_scroll", true) ? "on" : "off", v => Look.setInput({ pt_middle_scroll: v === "on" }))] : [],
      padRows(),
      [tab("Hotkeys"), info("Change a shortcut", "Open a group, click a combination and press the new keys (saved to ~/.config/niri/config.kdl)")],
      hotkeyRows()) }
  )
  readonly property var sec_preferences: (
    { id: "preferences", icon: "user", label: "Preferences", rows: [
      tab("Default apps"),
      header("Default apps"),
      cycle("Browser", "", apps("WebBrowser"), () => Prefs.get("default_browser", ""), v => Look.engine("da:1:" + v)),
      cycle("Files", "", apps("FileManager"), () => Prefs.get("default_files", ""), v => Look.engine("da:2:" + v)),
      cycle("Terminal", "", apps("TerminalEmulator"), () => Prefs.get("default_terminal", ""), v => Look.engine("da:3:" + v)),
      tab("Autostart"), header("Autostart")].concat(
      autostartApps.length
      ? autostartApps.map(a => choice(a.name, "", [["on", "On"], ["off", "Off"]],
               () => (autostartApps.find(x => x.path === a.path) || {}).on ? "on" : "off",
               v => { if ((v === "on") !== !!(autostartApps.find(x => x.path === a.path) || {}).on) toggleAutostart(a.path, v === "on") }))
      : [info("Autostart apps", "None found in ~/.config/autostart")],
      [tab("In the launcher", 10), header("Shown in the launcher")],
      appRows.map(([id, name]) => choice(name, "", [["on", "On"], ["off", "Off"]],
               () => appHidden(id) ? "off" : "on", v => { if ((v === "off") !== appHidden(id)) toggleAppHidden(id) }))
    ) }
  )
  readonly property var sec_storage: (
    { id: "storage", icon: "hard-drives", label: "Storage", rows: [].concat(
      [tab("Apps"), header("Installed apps · biggest first · a terminal asks before anything is removed")], storageAppRows(),
      [tab("Disks"), header("Space")], usageRows(), [header("Drives")], driveRows(),
      [tab("Mounting"), header("Mounted now")], mountRows(), [header("Not mounted")], unmountedRows(),
      [header("Network shares")], shareRows(),
      [tab("Care")], trimRows(),
      [header("Clean up"),
       Object.assign({ type: "action", label: "Clean up disk space", desc: "Opens a terminal: old package files (pacman -Sc, asks first) + unused Flatpak runtimes + thumbnail cache",
                       buttons: [["Clean up", cleanupNow]] }, { pin: "sys_cleanup" }),
       { type: "action", label: "Unused packages", desc: pkgs.unused < 0 ? "Checking…" : pkgs.unused ? pkgs.unused + " package(s) nothing needs (pacman -Rns, asks first)" : "None",
         buttons: pkgs.unused > 0 ? [[autoremoveArmed ? "Really remove?" : "Remove", () => {
           if (autoremoveArmed) { autoremoveArmed = false; autoremoveRun.running = true } else { autoremoveArmed = true; armTimer.restart() } }]] : [["Check again", () => pkgScan.running = true]] }]
    ) }
  )
  readonly property var sec_power: (
    { id: "power", icon: "lightning", label: "Power", rows: [].concat(
      [tab("Battery & buttons"), header("Power profile"),
       Object.assign(choice("Profile", "", [["power saver", "Saver"], ["balanced", "Balanced"], ["auto", "Auto"], ["performance", "Performance"]],
              () => Session.profile, v => Look.engine("pp:set:" + v)), { pin: "power_profile" }),
       choice("Lite mode in Saver", "Switch Lite on (no animations, blur) while the Saver profile is active", [["off", "Off"], ["on", "On"]],
              () => Prefs.get("lite_saver", false) === true ? "on" : "off", v => Prefs.set("lite_saver", v === "on"))],
      batRows(),
      [header("Lid and power button"),
       cycle("Close the lid", "On battery", logindOpts, () => logindGet("HandleLidSwitch", "suspend"), v => logindSet("lid", "HandleLidSwitch", v)),
       cycle("Close the lid on power", "Plugged in", logindOpts, () => logindGet("HandleLidSwitchExternalPower", "suspend"), v => logindSet("lid_ext", "HandleLidSwitchExternalPower", v)),
       cycle("Power button", "", logindOpts, () => logindGet("HandlePowerKey", "poweroff"), v => logindSet("power", "HandlePowerKey", v))],
      [tab("Sleep & lock"), header("On power: when idle"),
       cycle("Screen off after", "", minutes(withCur(idleSteps, Prefs.get("idle_screen", 10))), () => Number(Prefs.get("idle_screen", 10)), v => Look.oldSet("idle_screen", v)),
       cycle("Lock after", "", minutes(withCur(idleSteps, Prefs.get("idle_lock", 10))), () => Number(Prefs.get("idle_lock", 10)), v => Look.oldSet("idle_lock", v)),
       cycle("Sleep after", "", minutes(withCur(sleepSteps, Prefs.get("idle_sleep", 30))), () => Number(Prefs.get("idle_sleep", 30)), v => Look.oldSet("idle_sleep", v))],
      Session.bat && Session.bat.isLaptopBattery ? [header("On battery: when idle"),
       cycle("Screen off after", "", minutes(withCur(idleSteps, Prefs.get("idle_screen_bat", 2))), () => Number(Prefs.get("idle_screen_bat", 2)), v => Look.oldSet("idle_screen_bat", v)),
       cycle("Lock after", "", minutes(withCur(idleSteps, Prefs.get("idle_lock_bat", 2))), () => Number(Prefs.get("idle_lock_bat", 2)), v => Look.oldSet("idle_lock_bat", v)),
       cycle("Sleep after", "", minutes(withCur(sleepSteps, Prefs.get("idle_sleep_bat", 10))), () => Number(Prefs.get("idle_sleep_bat", 10)), v => Look.oldSet("idle_sleep_bat", v))] : []
    ) }
  )
  readonly property var sec_system: (
    { id: "system", icon: "gear", label: "System", rows: [].concat(
      [tab("Time & language"),
       header("Date & time"),
       cycle("Timezone", "", timezones.length ? timezones.map(z => [z, z.replace(/_/g, " ")]) : [[dateInfo.Timezone || "", dateInfo.Timezone || ""]],
             () => dateInfo.Timezone || "", v => setTimezone(v)),
       choice("Sync over network (NTP)", "", [["on", "On"], ["off", "Off"]],
              () => dateInfo.NTP === "yes" ? "on" : "off", v => setNtp(v === "on")),
       choice("Time format", "", [["24", "24-hour"], ["12", "12-hour"]],
              () => Prefs.get("clock_24h", true) ? "24" : "12", v => Prefs.set("clock_24h", v === "24")),
       choice("Seconds", "", [["off", "Off"], ["on", "On"]],
              () => Prefs.get("clock_seconds", false) ? "on" : "off", v => Prefs.set("clock_seconds", v === "on")),
       choice("Hardware clock", "Off is the Linux default", [["off", "Off"], ["on", "On"]],
              () => dateInfo.LocalRTC === "yes" ? "on" : "off",
              v => { Quickshell.execDetached(["pkexec", "timedatectl", "set-local-rtc", v === "on" ? "true" : "false"]); dateTimer.restart() }),
       header("Language"),
       cycle("System language (LANG)", "Applies to new sessions", locales.length ? locales.map(l => [l, l.replace(/\.UTF-?8$/i, "")]) : [[sysLang, sysLang]],
             () => sysLang, v => setLocale(v))],
      [tab("Updates"), header("Packages"),
       Object.assign(info("System packages (pacman)", updates.pac === -1 ? "Checking…" : updates.pac === -2 ? "Could not check (offline?)" : updates.pac + " update(s) available"), { pin: "sys_updates" }),
       { type: "action", label: "Update system", desc: "Opens a terminal: sudo pacman -Syu (a snapshot is taken before and after)", buttons: [["Update all", () => sysUpgrade.running = true], ["Check again", () => updatesScan.running = true]] },
       ...(updProgress > -2 ? [{ type: "progress", label: "Updating", value: updProgress, text: updText }] : (updText ? [info("Last update", updText)] : [])),
       ...(updates.flatpak ? [{ type: "action", label: "Flatpak apps", desc: "flatpak update -y", buttons: [["Update", () => flatpakUpgrade.running = true]] }] : []),
       header("Settings backup"),
       { type: "action", label: "Backup settings.toml", desc: "Timestamped copy next to the file", buttons: [["Back up", backupSettings], ["Restore latest", restoreSettings]] }],
      [tab("Advanced"),
       header("Mode"),
       choice("Expert mode", "Shows advanced hardware settings: ALSA mixer in Sound, drive formatting in Storage", [["off", "Off"], ["on", "On"]],
              () => Prefs.get("expert", false) === true ? "on" : "off", v => Prefs.set("expert", v === "on")),
       header("Network & remote access"),
       choice("SSH server (sshd)", "", [["off", "Off"], ["on", "On"]],
              () => netRemote.sshActive ? "on" : "off", v => toggleSsh(v === "on")),
       info("Firewall (nftables)", netRemote.fwEnabled ? "Rules load at boot (/etc/nftables.conf)" : "Not enabled"),
       info("DNS", netRemote.dns || ""),
       info("Network share", netRemote.share || "Not mounted"),
       header("Services (systemd --user)")], serviceRows(),
      [tab("Kernels", 8)], kernRows()
    ) }
  )
  readonly property var sec_gaming: (
    { id: "gaming", icon: "game-controller", label: "Gaming", rows: [].concat(
      hasAmdGpu ? [tab("GPU"), header("Sensors (live)"),   // module games adds the clock / voltage / power sliders to this tab
       info("Temperature", gpu.temp != null ? gpu.temp + " °C" : "—"),
       info("Power draw", gpu.power != null ? gpu.power + " W" : "—"),
       info("Clock", gpu.freq != null ? gpu.freq + " MHz" : "—"),
       info("Fan", gpu.fan != null ? gpu.fan + " RPM" : "—")] : [],
      [tab("Tuning"), header("Memory"),   // module games adds CachyOS repo, sched_ext and services here
       info("Swappiness (vm.swappiness)", swappiness || "—")]
    ) }
  )
  readonly property var sec_about: (
    { id: "about", icon: "info", label: "About", rows: [
      header("This computer"),
      info("System", (System.about.os || "") + " · " + (System.about.host || "")),
      info("Kernel", System.about.kernel || ""),
      info("Shell", "LWTS on Quickshell " + (System.about.qs || "")),
      info("CPU", System.about.cpu || ""),
      info("GPU", System.about.gpu || ""),
      info("RAM", System.about.ram || ""),
      info("Uptime", System.about.uptime || ""),
    ] }
  )
  readonly property var rawBody: [sec_wifi, sec_bluetooth, sec_network, sec_sound, sec_notifications, sec_appearance, sec_devices,
                                  sec_preferences, sec_storage, sec_power, sec_gaming, sec_system, sec_about].filter(s => !!s)

  // ---- nested navigation (Windows-style: category -> subpage list -> page), derived for free from the
  // existing header() rows - no section's row data changes, a header just also becomes a subpage boundary.
  // A section with 0-1 headers (Pinned; any section with a single card) has exactly one group and skips the
  // subpage list, going straight side -> page exactly as before - no extra click for the simple sections.
  function groupsOf(sec) {
    if (!sec || !sec.rows) return [{ label: "", rows: [] }];   // section index briefly past the list (modules changed): no TypeError
    const gs = [];
    let cur = null;
    for (const r of sec.rows) {   // a tab label seen again (a module adding to a base tab) continues that group
      if (r.type === "tab") { cur = gs.find(g => g.label === r.label) || null; if (cur && r.page && !cur.pageSize) cur.pageSize = r.page; if (!cur) { cur = { label: r.label, rows: [], isGrid: !!r.grid, pageSize: r.page || 0 }; gs.push(cur) } }
      else { if (!cur) { cur = { label: sec.label, rows: [] }; gs.push(cur) } cur.rows.push(r) }
    }
    return gs.length ? gs : [{ label: sec.label, rows: sec.rows }];
  }
  readonly property var groups: groupsOf(sections[section])
  readonly property bool onGrid: !!(groups[group] && groups[group].isGrid)

  property int section: 0
  property string pane: "side"   // side | group | page
  property int group: 0
  property int row: 0
  property int chip: 0           // focused chip / button inside a multi or action row
  // choice / cycle rows: arrows only move this cursor (starts on the current value), Enter applies - nothing changes by passing
  property int cursor: 0
  property bool keyNav: false    // focus rings only after a key press (like :focus-visible); a click hides them
  // controls like Windows / macOS: On/Off = switch, 2-3 values = segmented, more = drop-down list
  function isSwitch(r) { return r && r.type === "choice" && !r.preview && r.options.length === 2
                           && String(r.options[0][1]).toLowerCase() === "on" && String(r.options[1][1]).toLowerCase() === "off"
                           || !!r && r.type === "choice" && !r.preview && r.options.length === 2
                           && String(r.options[0][1]).toLowerCase() === "off" && String(r.options[1][1]).toLowerCase() === "on" }
  function switchOn(r) { const on = r.options.find(o => String(o[1]).toLowerCase() === "on"); return String(r.get()) === String(on[0]) }
  function toggleSwitch(r) { const to = r.options.find(o => String(o[1]).toLowerCase() === (switchOn(r) ? "off" : "on")); r.set(to[0]) }
  property int hintRow: -1       // row whose "i" bubble is open (-1 = none); hidden when the focus leaves the row
  property int ddRow: -1          // row whose drop-down list is open (-1 = none)
  property int ddIndex: 0
  property string ddType: ""
  Timer { id: ddTypeTimer; interval: 900; onTriggered: st.ddType = "" }
  property int inputReq: 0   // keyboard: the focused input row starts editing (onInputReqChanged)
  property int ddReq: 0     // keyboard open: the row's button positions the list (onDdReqChanged)
  property int ddReqRow: -1  // which row asked (ddRow itself is set by openDd, after the start rect)
  property bool ddJump: false   // the card snaps to the button before unfolding (no flight from the last place)
  property real ddX: 0
  property real ddY: 0
  property real ddW: 160
  property bool ddUp: false
  property var ddOpts: []         // kept after closing, so the list can fade out
  property real ddOriginY: 0      // the button's centre inside the list: it grows out of there
  property rect ddB: Qt.rect(0, 0, 0, 0)   // the button: the list unfolds out of it and folds back into it
  function openDd(i, item) {
    const r = rows[i]; if (!r || !r.options) return;
    const o = r.options, cur = Math.max(0, o.findIndex(x => String(x[0]) === String(r.get())));
    // the button stretches into the list: same width, rows as tall as the button, the current row exactly where the button was
    const h = Math.min(o.length * 24, 240), pt = item.mapToItem(st, 0, 0);
    ddW = item.width; ddX = pt.x;
    ddY = Math.max(4, Math.min(st.height - h - 4, pt.y - Math.min(cur, Math.floor(h / 24) - 1) * 24)); ddUp = false;
    ddOriginY = pt.y + item.height / 2 - ddY;
    ddJump = true; ddUnfold = false; ddB = Qt.rect(pt.x, pt.y, item.width, item.height); ddJump = false;
    ddKeepOff.stop(); ddKeep = true; ddOpts = o; ddArmed = false; ddArm.restart(); ddIndex = cur; ddRow = i; ddLast = i;
    ddUnfold = false; ddGo.restart()   // a rendered frame at the button first (the layer's first paint is slow), then unfold
  }
  function closeDd() { ddGo.stop(); ddRow = -1; ddArmed = false; ddUnfold = false; ddKeepOff.restart() }
  property bool ddKeep: false      // the card is drawn: set at once on open, dropped after the fold-back
  Timer { id: ddKeepOff; interval: Motion.dropClose; onTriggered: if (st.ddRow < 0) st.ddKeep = false }
  Timer { id: ddGo; interval: 50; onTriggered: if (st.ddRow >= 0) st.ddUnfold = true }
  property bool ddUnfold: false
  property int ddLast: -1          // the row whose button turned into the list: hidden while the list is out
  readonly property bool ddShown: ddLayer.visible
  property bool ddArmed: false
  Timer { id: ddArm; interval: 350; onTriggered: st.ddArmed = true }
  Timer { id: ddHear; interval: 170; onTriggered: { const r = st.rows[st.ddRow]; if (st.ddArmed && r && r.hover) r.hover(r.options[st.ddIndex][0]) } }
  onDdIndexChanged: if (ddRow >= 0) ddHear.restart()
  function applyDd() { const r = rows[ddRow]; if (r) r.set(r.options[ddIndex][0]); closeDd() }
  function syncCursor() { const r = rows[row]; cursor = r && r.options && r.get ? Math.max(0, r.options.findIndex(o => String(o[0]) === String(r.get()))) : 0 }
  onRowChanged: syncCursor()
  onPaneChanged: syncCursor()
  property int rowCap: 0
  onRowsChanged: if (rows.length > rowCap) rowCap = rows.length
  readonly property var rowsAll: filter === "" ? (groups[group] ? groups[group].rows : [])
                              : [].concat(...body.map(s => s.rows)).filter(r => r.type !== "header" && r.type !== "tab" && r.label.toLowerCase().includes(filter.toLowerCase()))
  // long lists (tab(label, pageSize)): one page at a time, dots under the tabs, PageUp / PageDown or Up / Down past the edge flips - never a scroll
  property int pageNo: 0
  readonly property int pageSize: 0   // v5: paging removed (wide window instead); the tab(label, pageSize) argument is ignored
  // pages break between cards (a header starts a card) so a header never ends a page alone; a card longer than a page is cut every pageSize rows
  function splitPages(all, n) {
    const pages = []; let cur = [], i = 0;
    while (i < all.length) {
      let j = i + 1; while (j < all.length && all[j].type !== "header") j++;
      let card = all.slice(i, j);
      while (card.length > n) { if (cur.length) { pages.push(cur); cur = [] } pages.push(card.slice(0, n)); card = card.slice(n) }
      if (cur.length && cur.length + card.length > n) { pages.push(cur); cur = [] }
      cur = cur.concat(card); i = j;
    }
    if (cur.length) pages.push(cur);
    return pages.length ? pages : [[]];
  }
  readonly property var pagesAll: pageSize > 0 ? splitPages(rowsAll, pageSize) : [rowsAll]
  readonly property int pageCount: pagesAll.length
  readonly property int pageCur: Math.min(pageNo, pageCount - 1)
  readonly property var rows: pagesAll[pageCur] || []
  function lastRow() { for (let i = rows.length - 1; i >= 0; i--) if (selectable(i)) return i; return 0 }
  function setPage(n, last) { const c = Math.max(0, Math.min(pageCount - 1, n)); if (c === pageCur) return; pageNo = c; row = last ? lastRow() : firstRow(); chip = 0; rowsFade.restart() }
  onFilterChanged: { pageNo = 0; row = firstRow(); if (filter !== "") pane = "page"; updSoundOpen() }
  onSectionChanged: { pageNo = 0; chip = 0; group = 0; updSoundOpen(); pageFade.restart() }
  onGroupChanged: { pageNo = 0; rowsFade.restart() }
  // switching: opacity + a few px of offset only (no layout per frame), so it stays smooth at 60 Hz
  property real pageIn: 1
  property real rowsIn: 1
  // linear driver: fade done by 60%, the rise eases out (cubic) over the whole run; 14 px so it never crawls sub-pixel at 60 Hz
  NumberAnimation { id: pageFade; target: st; property: "pageIn"; from: 0; to: 1; duration: Motion.off ? 0 : 320 }
  NumberAnimation { id: rowsFade; target: st; property: "rowsIn"; from: 0; to: 1; duration: Motion.off ? 0 : 300 }
  function fadeOf(p) { return Math.min(1, p / 0.6) }
  function riseOf(p, px) { return Math.round(px * Math.pow(1 - p, 3)) }
  function backFromPage() { pane = groups.length > 1 ? "group" : "side" }
  function reset() { section = 0; pane = "side"; group = 0; row = 0; keyNav = false; endCapture(); System.refresh() }
  function selectable(i) { const r = rows[i]; return !!r && r.type !== "header" && r.type !== "info" && r.type !== "progress" }
  function firstRow() { for (let i = 0; i < rows.length; i++) if (selectable(i)) return i; return 0 }
  function step(d) { let i = row; do { i += d } while (i >= 0 && i < rows.length && !selectable(i)); if (i >= 0 && i < rows.length) { row = i; chip = 0 } else if (pageCount > 1) setPage(pageCur + (d > 0 ? 1 : -1), d < 0) }

  function cycleRow(r, d) {
    const vals = r.options.map(o => o[0]); const i = vals.findIndex(v => String(v) === String(r.get()));
    r.set(vals[(Math.max(0, i) + d + vals.length) % vals.length]);
  }
  function handleKey(e) {   // true = used
    keyNav = true;
    const k = e.key, r = rows[row];
    if ((k === Qt.Key_PageDown || k === Qt.Key_PageUp) && pageCount > 1 && ddRow < 0 && !capturing && pane === "page") { setPage(pageCur + (k === Qt.Key_PageDown ? 1 : -1), false); return true }
    if (capturing) {   // recording new keys for a hotkey
      if (k === Qt.Key_Escape) endCapture();
      else { const n = keyName(e); if (n) { setRebind(capturing, n); endCapture() } }
      return true;
    }
    if (ddRow >= 0) {   // an open drop-down list owns the keys
      const n = rows[ddRow].options.length;
      if (e.text.length === 1 && e.text >= " " && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {   // type-ahead: jump to the first match
        ddType = (ddType + e.text).toLowerCase(); ddTypeTimer.restart();
        const j = rows[ddRow].options.findIndex(o => String(o[1]).toLowerCase().startsWith(ddType));
        if (j >= 0) ddIndex = j;
        return true;
      }
      if (k === Qt.Key_Down) ddIndex = Math.min(ddIndex + 1, n - 1);
      else if (k === Qt.Key_Up) ddIndex = Math.max(ddIndex - 1, 0);
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) applyDd();
      else closeDd();   // Esc or anything else
      return true;
    }
    if (pane === "side") {
      if (k === Qt.Key_Down) section = Math.min(section + 1, sections.length - 1);
      else if (k === Qt.Key_Up) section = Math.max(section - 1, 0);
      else if (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter) {
        if (groups.length > 1) { pane = "group"; group = 0 }
        else if (rows.length || onGrid) { pane = "page"; row = firstRow() }
        else return false;
      }
      else return false;
      return true;
    }
    if (pane === "group") {   // the tab strip: ← → switch (content follows at once), ↓ / Enter into the page
      if (k === Qt.Key_Right) group = Math.min(group + 1, groups.length - 1);
      else if (k === Qt.Key_Left) { if (group === 0) pane = "side"; else group = group - 1 }
      else if (k === Qt.Key_Escape) pane = "side";
      else if ((k === Qt.Key_Down || k === Qt.Key_Return || k === Qt.Key_Enter) && (rows.length || onGrid)) { pane = "page"; row = firstRow() }
      else return false;
      return true;
    }
    if (k === Qt.Key_Escape) { if (filter !== "") return false; backFromPage(); return true }
    if (onGrid) {
      if (tileConstructor.handleKey(e)) return true;
      if (k === Qt.Key_Left || k === Qt.Key_Up) { backFromPage(); return true }
      return false;
    }
    if (!r) return false;
    if (k === Qt.Key_L && r && r.play && filter === "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { r.play(); return true }
    if (k === Qt.Key_P && r.pin && filter === "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { togglePin(r.pin); return true }
    if (r.type === "slider" && (k === Qt.Key_Left || k === Qt.Key_Right)) {
      const sorted = r.steps.slice().sort((a, b) => a - b), cur = Number(r.get());
      if (k === Qt.Key_Left && cur <= sorted[0] && filter === "") { backFromPage(); return true }
      const i = sorted.reduce((b, v, j) => Math.abs(v - cur) < Math.abs(sorted[b] - cur) ? j : b, 0);
      const v = sorted[Math.max(0, Math.min(sorted.length - 1, i + (k === Qt.Key_Right ? 1 : -1)))];
      if (v !== cur) r.set(v);
      return true;
    }
    if ((r.type === "keytest" || r.type === "kbmap") && k !== Qt.Key_Up && k !== Qt.Key_Down && k !== Qt.Key_Escape) {
      if (r.type === "kbmap") kbPress(e);
      const n = keyName(e), kk = r.type === "kbmap" ? kbKeys.find(x => x.code === e.nativeScanCode - 8) : null;
      lastKey = n || (kk && kk.label) || ("key " + k); return true
    }
    if (r.type === "monmap") {
      if (k >= Qt.Key_1 && k <= Qt.Key_9) { monSel = Math.min(k - Qt.Key_1, System.monitors.length - 1); return true }
      const side = ({ [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down" })[k];
      if (side && (e.modifiers & Qt.ShiftModifier)) { monMove(side); return true }
    }
    const n = r.type === "multi" ? r.options.length : r.type === "action" ? r.buttons.length : 0;
    if (k === Qt.Key_Down) step(1);
    else if (k === Qt.Key_Up && row <= firstRow() && groups.length > 1 && filter === "") pane = "group";
    else if (k === Qt.Key_Up) step(-1);
    else if (r.type === "picker" && (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter)) pick(r.kind);
    else if (r.type === "hotkey") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (r.removed) restoreBind(r.keys); else startCapture(r.keys) }
      else if (k === Qt.Key_Delete) { if (!r.removed) setRebind(r.keys, "") }
      else if (k === Qt.Key_Backspace) { if (r.def) setRebind(r.keys, r.def) }
      else if (k === Qt.Key_Left && filter === "") backFromPage();
      else return false;
    }
    else if (n && k === Qt.Key_Right) chip = Math.min(chip + 1, n - 1);
    else if (n && k === Qt.Key_Left) { if (chip === 0 && filter === "") backFromPage(); else chip = Math.max(chip - 1, 0) }
    else if (r.type === "multi" && (k === Qt.Key_Return || k === Qt.Key_Enter)) r.toggle(r.options[chip][0]);
    else if (r.type === "action" && (k === Qt.Key_Return || k === Qt.Key_Enter)) r.buttons[chip][1]();
    else if (r.type === "input" && (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Right && filter === ""))) inputReq++
    else if (r.type === "input" && k === Qt.Key_Left && filter === "") backFromPage();
    else if (k === Qt.Key_I && filter === "" && r.hint) hintRow = hintRow === row ? -1 : row;
    else if (r.type === "cycle" && k === Qt.Key_Left && filter === "") backFromPage();
    else if (r.type === "cycle" && (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Space && filter === ""))) { ddReqRow = row; ddReq++ }
    else if ((r.type === "choice" || r.type === "cycle") && k === Qt.Key_Right) cursor = Math.min(cursor + 1, r.options.length - 1);
    else if ((r.type === "choice" || r.type === "cycle") && k === Qt.Key_Left) { if (cursor <= 0 && filter === "") backFromPage(); else cursor = Math.max(cursor - 1, 0) }
    else if (isSwitch(r) && (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Space && filter === ""))) toggleSwitch(r);
    else if (r.type === "choice" && (k === Qt.Key_Return || k === Qt.Key_Enter)) r.set(r.options[cursor][0]);
    else return false;
    return true;
  }

  // ---- look -------------------------------------------------------------------------------
  component Label: Text { color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); verticalAlignment: Text.AlignVCenter }
  // The look of these lives in widgets/Ui*.qml (one definition each); the names stay so the call sites below need no edits.
  component Switch: UiToggle {}
  component Seg: UiSeg {}
  component Chip: UiButton {}

  RowLayout {
    anchors.fill: parent
    spacing: 8

    Rectangle {   // sidebar-box: icons only while a category is open, full again on hover or back in the list
      id: sideBox
      visible: st.filter === ""
      readonly property bool collapsed: false   // v5: always icon + label (Android-like list); was icons-only while a page is open //   // keys: full while the cursor is in the list; mouse: always icons (no hover switching, the layout used to jump under the pointer)
      Layout.preferredWidth: collapsed ? 40 : 176; Layout.fillHeight: true
      Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.game ? 0 : Motion.fit(Motion.normal); easing.type: Motion.type; easing.bezierCurve: Motion.emphasized } }
      clip: true
      radius: Theme.radiusInner
      color: "transparent"; border.width: 1; border.color: Theme.line   // Nothing: outlined sidebar
      Column {
        id: sideCol
        anchors { fill: parent; margins: 4 }
        spacing: 2
        Repeater {
          model: st.sections
          MouseArea {
            required property var modelData
            required property int index
            readonly property bool current: st.section === index
            width: parent.width; height: 32
            cursorShape: Qt.PointingHandCursor
            onClicked: { st.section = index; st.pane = "side"; st.group = 0; st.row = 0 }
            Rectangle {   // Nothing: icons-only = round buttons; the open section = a solid accent plate
              anchors.fill: parent; radius: Theme.radiusCtl
              color: parent.current ? Theme.accent : "transparent"   // Nothing: the open section = a solid accent plate
            }
            Row {
              anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
              spacing: 7
              Icon { name: modelData.icon; color: current ? Theme.accentInk : Theme.text; anchors.verticalCenter: parent.verticalCenter }
              Label { text: modelData.label; color: current ? Theme.accentInk : Theme.text; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
                      opacity: sideBox.collapsed ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Motion.fit(Motion.fast); easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } } }
            }
          }
        }
      }
    }

    Flickable {   // page
      id: page
      Layout.fillWidth: true; Layout.fillHeight: true
      clip: true
      contentHeight: card.height
      boundsBehavior: Flickable.StopAtBounds
      function show(item) { if (item.y < contentY) contentY = item.y; else if (item.y + item.height > contentY + height) contentY = item.y + item.height - height }

      readonly property bool isQuick: st.onGrid && st.filter === ""
      Label { visible: st.rows.length === 0 && !page.isQuick; text: "Nothing found"; color: Theme.dim; topPadding: 6 }

      Item {   // the page: title, then cards - a header row starts a new card (macOS / GNOME)
        id: card
        visible: st.rows.length > 0 || page.isQuick || st.groups.length > 1
        width: page.width; height: cardCol.implicitHeight
        Column {
          id: cardCol
          width: parent.width
          opacity: st.fadeOf(st.pageIn)
          transform: Translate { y: st.riseOf(st.pageIn, 14) }
          UiNum {   // page title = the section: dot-matrix headline (user: more dot font)
            size: Math.round(32 * Theme.scale)
            visible: st.filter === ""
            text: st.sections[st.section].label
            leftPadding: 4; bottomPadding: 4
          }
          Item {   // tabs = settings_spec subsections: a strip like niri's columns - tabs as wide as their text (+ the spare room when
                   // they all fit), the current one glides to the centre, the underline slides after it, the wheel scrolls the strip
            id: tabBar
            visible: st.filter === "" && st.groups.length > 1
            width: parent.width; height: visible ? 34 : 0
            FontMetrics { id: tabFm; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale) }   // tabs = mono caps
            readonly property var natural: st.groups.map(g => Math.ceil(tabFm.advanceWidth(g.label)) + 28)
            readonly property real naturalSum: natural.reduce((x, y) => x + y, 0)
            readonly property bool fits: naturalSum <= width
            function tabW(i) { return natural[i] + (fits ? (width - naturalSum) / natural.length : 0) }   // spare room shared, a label is never cut
            function tabX(i) { let x = 0; for (let j = 0; j < i; j++) x += tabW(j); return x }
            function centre() {   // the current tab in the middle of the strip, clamped to its ends
              if (fits) { tabFlick.contentX = 0; return }
              tabFlick.contentX = Math.max(0, Math.min(tabRow.width - tabFlick.width, tabX(st.group) + tabW(st.group) / 2 - tabFlick.width / 2));
            }
            Connections { target: st; function onGroupChanged() { tabBar.centre() } function onGroupsChanged() { tabBar.centre() } }
            onWidthChanged: centre()
            Flickable {
              id: tabFlick
              anchors { left: parent.left; right: parent.right; top: parent.top }
              height: 28; clip: true
              contentWidth: tabRow.width; contentHeight: height
              interactive: !tabBar.fits; boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.HorizontalFlick
              Behavior on contentX { enabled: !tabFlick.moving; NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
              WheelHandler {   // vertical wheel = sideways, like niri
                enabled: !tabBar.fits
                onWheel: e => { const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                                tabFlick.contentX = Math.max(0, Math.min(tabRow.width - tabFlick.width, tabFlick.contentX - d / 2)) }
              }
              Row {
                id: tabRow
                height: parent.height
                Repeater {
                  model: st.groups
                  MouseArea {
                    id: tabItem
                    required property var modelData
                    required property int index
                    readonly property bool cur: st.group === index
                    width: tabBar.tabW(index); height: parent.height
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { st.group = index; st.pane = "group"; st.row = 0 }
                    Rectangle { anchors { fill: parent; margins: 2 } radius: Theme.radiusInner
                                color: tabItem.cur && st.pane === "group" ? Theme.tint : tabItem.containsMouse ? Theme.fill : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.duration } } }
                    Label { anchors.centerIn: parent; width: parent.width - 8; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: tabItem.modelData.label; color: tabItem.cur ? Theme.accent : Theme.dim
                            font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
                            Behavior on color { ColorAnimation { duration: Motion.duration } } }
                  }
                }
              }
              Rectangle {   // one underline that slides to the current tab
                y: parent.height - 2; height: 2; radius: 1; color: Theme.accent
                x: tabBar.tabX(st.group) + 8; width: Math.max(0, tabBar.tabW(st.group) - 16)
                Behavior on x { NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
                Behavior on width { NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
              }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 28 } height: 1; color: Theme.line }
          }
          Row {   // pager of a long list: < dots n/N >  (click, PageUp / PageDown)
            visible: st.pageCount > 1
            height: visible ? 26 : 0; spacing: 8; leftPadding: 4
            Label { text: "‹"; color: st.pageCur > 0 ? Theme.text : Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(15 * Theme.scale); anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: st.setPage(st.pageCur - 1, false) } }
            Repeater {
              model: st.pageCount <= 8 ? st.pageCount : 0
              Rectangle { required property int index; width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter
                color: index === st.pageCur ? Theme.accent : Theme.line
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: st.setPage(parent.index, false) } }
            }
            Label { text: (st.pageCur + 1) + " / " + st.pageCount; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale); anchors.verticalCenter: parent.verticalCenter }
            Label { text: "›"; color: st.pageCur < st.pageCount - 1 ? Theme.text : Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(15 * Theme.scale); anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: st.setPage(st.pageCur + 1, false) } }
          }
          QsConstructor {
            id: tileConstructor
            visible: page.isQuick
            width: cardCol.width
          }
          Repeater {   // the count only grows: a new count recreated every row (~70 items each, 25-135 ms per section switch)
            model: st.rowCap
            Item {
              id: rowItem
              required property int index
              visible: index < st.rows.length
              opacity: st.fadeOf(st.rowsIn)
              transform: Translate { x: st.riseOf(st.rowsIn, 12) }
              readonly property var r: st.rows[index] || ({ type: "header", label: "" })
              readonly property bool focused: st.pane === "page" && st.row === index
              readonly property bool tall: !!r.desc && r.type !== "header"
              z: st.hintRow === index ? 50 : 0
              width: cardCol.width
              readonly property bool groupStart: index === 0 || (st.rows[index - 1] || {}).type === "header"
              readonly property bool groupEnd: index === st.rows.length - 1 || (st.rows[index + 1] || {}).type === "header"
              height: r.type === "header" ? (index === 0 ? 28 : 44) : r.preview ? 100 : r.type === "monmap" ? 200 : r.type === "fontpreview" ? 84 : r.type === "cursortest" || r.type === "mousetest" ? 70 : r.type === "keytest" ? 48 : r.type === "progress" ? 44 : r.type === "kbmap" ? Math.round(190 * Theme.scale) : r.type === "padview" ? padLoader.implicitHeight + 16 : r.type === "padwiz" ? wizLoader.implicitHeight + 16 : r.type === "multi" ? (tall ? 50 : 40) + chips.implicitHeight + 4 : tall ? 52 : 42   // Nothing: airy rows
              onFocusedChanged: if (focused) page.show(rowItem)
              HoverHandler { id: rowHover }
              MouseArea {   // the whole row: picker opens, others take focus
                anchors.fill: parent
                enabled: rowItem.r.type !== "header"
                cursorShape: rowItem.r.type === "picker" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; if (rowItem.r.type === "picker") st.pick(rowItem.r.kind) }
              }
              Rectangle {   // this row's piece of its group card: rounded at the group's ends, a hairline between rows
                visible: rowItem.r.type !== "header"
                width: parent.width; height: parent.height
                color: "transparent"   // Nothing: no card plates - rows on the black field, hairlines above each row and under the group
                UiDotLine { width: parent.width }   // Nothing: dotted rules between rows
                UiDotLine { visible: rowItem.groupEnd; anchors.bottom: parent.bottom; width: parent.width }
                topLeftRadius: rowItem.groupStart ? Theme.radiusCard : 0; topRightRadius: rowItem.groupStart ? Theme.radiusCard : 0
                bottomLeftRadius: rowItem.groupEnd ? Theme.radiusCard : 0; bottomRightRadius: rowItem.groupEnd ? Theme.radiusCard : 0
              }
              Rectangle { anchors { fill: parent; margins: 3 } radius: Theme.radiusInner; color: rowItem.focused ? Theme.tint : "transparent" }

              UiCaption {   // group header
                visible: rowItem.r.type === "header"
                anchors { left: parent.left; leftMargin: 4; bottom: parent.bottom; bottomMargin: 5 }
                text: rowItem.r.label
              }
              Column {   // label + description
                visible: ["header", "monmap", "cursortest", "fontpreview", "mousetest", "keytest", "kbmap", "progress", "padview", "padwiz"].indexOf(rowItem.r.type) < 0
                anchors { left: parent.left; leftMargin: 10; verticalCenter: rowItem.r.type === "multi" ? undefined : parent.verticalCenter
                          top: rowItem.r.type === "multi" ? parent.top : undefined; topMargin: 7 }
                width: rowItem.r.type === "multi" ? parent.width - 20 : parent.width * 0.45
                Label { text: rowItem.r.label; width: parent.width; elide: Text.ElideRight }
                Label { visible: rowItem.tall; text: rowItem.r.desc || ""; color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale)
                        width: parent.width; elide: Text.ElideRight }
              }

              Flow {   // multi: chips on their own line under the label (they do not fit beside it)
                id: chips
                visible: rowItem.r.type === "multi"
                anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 8 }
                spacing: 3
                  Repeater {   // multi: chips on / off
                    model: rowItem.r.type === "multi" ? rowItem.r.options : []
                    Chip {
                      required property var modelData
                      required property int index
                      text: modelData[1]; on: rowItem.r.isOn(modelData[0]); focusedChip: st.keyNav && rowItem.focused && st.chip === index
                      onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; st.chip = index; rowItem.r.toggle(modelData[0]) }
                    }
                }
              }
              MouseArea {   // cursor tester (settings_spec 3.6): hover = the real pointer at its size, click = a ring where it hit
                id: curTest
                visible: rowItem.r.type === "cursortest"
                anchors { fill: parent; margins: 6 }
                hoverEnabled: visible; acceptedButtons: Qt.AllButtons
                Label { anchors.centerIn: parent; color: Theme.dim; font.pixelSize: Math.round(11 * Theme.scale)
                        text: curTest.containsMouse ? "Click anywhere here" : "Hover here to see the pointer at this size" }
                onClicked: m => { ring.x = m.x - ring.width / 2; ring.y = m.y - ring.height / 2; ring.opacity = 1; ringFade.restart() }
                Rectangle { id: ring; width: 24; height: 24; radius: 12; color: "transparent"; border.width: 2; border.color: Theme.accent; opacity: 0
                            NumberAnimation on opacity { id: ringFade; running: false; to: 0; duration: 500 } }
              }
              Column {   // font preview (settings_spec 3.6): the interface font as it is right now
                visible: rowItem.r.type === "fontpreview"
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                spacing: 2
                Text { text: "Aa Яя 0123 — " + Theme.font; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(20 * Theme.scale) }
                Text { text: "Швидка бура лисиця · The quick brown fox"; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(13 * Theme.scale) }
                Text { text: "Wi-Fi · 14:52 · 96%"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
              }
              Item {   // keyboard map: the key you press lights up (only this row, only while it has the focus)
                visible: rowItem.r.type === "kbmap"
                anchors { fill: parent; margins: 8 }
                readonly property real u: Math.min(width / 15.2, (height - 24) / 6.4)
                Repeater {
                  model: rowItem.r.type === "kbmap" ? st.kbKeys : []
                  Rectangle {
                    required property var modelData
                    readonly property bool lit: !!st.kbLit[modelData.code]
                    x: modelData.x * parent.u + (parent.width - 15.2 * parent.u) / 2; y: modelData.y * parent.u + (modelData.y > 0 ? parent.u * 0.4 : 0)
                    width: modelData.w * parent.u - 3; height: parent.u - 3; radius: 3
                    color: lit ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                    Behavior on color { ColorAnimation { duration: Motion.fit(Motion.fast * 0.65) } }
                    Text { anchors.centerIn: parent; text: parent.modelData.label; color: parent.lit ? Theme.accentInk : Theme.dim
                           font.family: Theme.font; font.pixelSize: Math.max(7, Math.round(parent.parent.u * 0.34)) }
                  }
                }
                Label { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        text: !rowItem.focused ? "Select this row, then press keys" : st.lastKey ? st.lastKey : "Press any key"
                        color: st.lastKey && rowItem.focused ? Theme.accent : Theme.dim; font.pixelSize: Math.round(11 * Theme.scale) }
              }
              Item {   // progress: a bar and the last line of the task (value -1 = no numbers yet)
                visible: rowItem.r.type === "progress"
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                Label { id: pgl; anchors { left: parent.left; top: parent.top; topMargin: 4 } text: rowItem.r.type === "progress" ? rowItem.r.label : "" }
                Label { anchors { right: parent.right; top: parent.top; topMargin: 4 } text: rowItem.r.type === "progress" ? rowItem.r.text : ""; color: Theme.dim; elide: Text.ElideLeft
                        width: parent.width - pgl.implicitWidth - 16; horizontalAlignment: Text.AlignRight; font.pixelSize: Math.round(11 * Theme.scale) }
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
                  height: 4; radius: 2; color: Theme.line; clip: true
                  Rectangle { height: parent.height; radius: 2; color: Theme.accent
                              width: rowItem.r.type === "progress" && rowItem.r.value >= 0 ? parent.width * rowItem.r.value : parent.width * 0.25
                              Behavior on width { NumberAnimation { duration: Motion.fit(Motion.normal); easing.type: Motion.type; easing.bezierCurve: Motion.emphasized } }
                              NumberAnimation on x { running: rowItem.r.type === "progress" && rowItem.r.value < 0; loops: Animation.Infinite; from: -parent.width * 0.25; to: parent.width; duration: 1200 } }
                }
              }
              Label {   // key tester (settings_spec 6.1): focus the row, press anything; ↑ ↓ Esc still navigate
                visible: rowItem.r.type === "keytest"
                anchors.centerIn: parent; color: st.lastKey ? Theme.accent : Theme.dim; font.pixelSize: Math.round((st.lastKey ? 14 : 11) * Theme.scale)
                text: !rowItem.focused ? "Select this row, then press keys" : st.lastKey ? st.lastKey.replace(/ \+ /g, " + ") : "Press any key or combo…"
              }
              Loader {   // gamepad: the live picture of the part being tuned
                id: padLoader
                active: rowItem.r.type === "padview"
                visible: active
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                sourceComponent: GamepadView { pad: st.curPad; part: rowItem.r.part || "l" }
              }
              Loader {   // calibration wizard: the whole tab while PadCal.wiz is set
                id: wizLoader
                active: rowItem.r.type === "padwiz"
                visible: active
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                sourceComponent: PadWizard { pad: st.curPad }
              }
              MouseArea {   // mouse tester (settings_spec 6.1): buttons and wheel light up
                id: mouseTest
                visible: rowItem.r.type === "mousetest"
                anchors { fill: parent; margins: 6 }
                hoverEnabled: visible; acceptedButtons: Qt.AllButtons
                property string last: ""
                property int wheel: 0
                onPressed: m => last = m.button === Qt.LeftButton ? "Left" : m.button === Qt.RightButton ? "Right" : m.button === Qt.MiddleButton ? "Middle"
                                     : m.button === Qt.BackButton ? "Back" : m.button === Qt.ForwardButton ? "Forward" : "Button " + m.button
                onReleased: last = last + " ✓"
                onWheel: w => { wheel += w.angleDelta.y > 0 ? 1 : -1; last = "Wheel " + (w.angleDelta.y > 0 ? "up" : "down") + " (" + wheel + ")" }
                Label { anchors.centerIn: parent; color: mouseTest.last ? Theme.accent : Theme.dim
                        text: mouseTest.last || (mouseTest.containsMouse ? "Click any button or scroll" : "Mouse tester — click or scroll here") }
              }
              Item {   // monitor map (settings_spec 9.1): drag = attach to the nearest side, 1-9 select, Shift+arrows attach
                id: monMap
                visible: rowItem.r.type === "monmap"
                anchors { fill: parent; margins: 10; topMargin: 24 }
                readonly property var mons: rowItem.r.type === "monmap" ? st.monLogical() : []
                readonly property real minX: mons.length ? Math.min(...mons.map(m => m.x)) : 0
                readonly property real minY: mons.length ? Math.min(...mons.map(m => m.y)) : 0
                readonly property real spanW: mons.length ? Math.max(...mons.map(m => m.x + m.w)) - minX : 1
                readonly property real spanH: mons.length ? Math.max(...mons.map(m => m.y + m.h)) - minY : 1
                readonly property real k: Math.min(width / spanW, height / spanH) * 0.92
                readonly property real ox: (width - spanW * k) / 2
                readonly property real oy: (height - spanH * k) / 2
                Label { y: -18; text: "Arrangement · drag, or 1–9 select and Shift+arrows · reverts in 12 s unless kept"
                        color: Theme.dim; font.pixelSize: Math.round(11 * Theme.scale) }
                Repeater {
                  model: monMap.mons
                  Rectangle {
                    id: mrect
                    required property var modelData
                    required property int index
                    readonly property bool sel: st.monSel === index
                    x: monMap.ox + (modelData.x - monMap.minX) * monMap.k
                    y: monMap.oy + (modelData.y - monMap.minY) * monMap.k
                    width: modelData.w * monMap.k; height: modelData.h * monMap.k
                    radius: Theme.radiusInner
                    color: sel ? Theme.tint : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.6)
                    border.width: sel && rowItem.focused ? 2 : 1; border.color: sel ? Theme.accent : Theme.line
                    Label { anchors.centerIn: parent; text: (mrect.index + 1) + " · " + mrect.modelData.name; color: mrect.sel ? Theme.accent : Theme.text }
                    MouseArea {
                      anchors.fill: parent; cursorShape: Qt.OpenHandCursor
                      drag.target: mrect; drag.threshold: 3
                      onPressed: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; st.monSel = mrect.index }
                      onReleased: st.monDrop(mrect.index, monMap.minX + (mrect.x - monMap.ox) / monMap.k,
                                             monMap.minY + (mrect.y - monMap.oy) / monMap.k, 24 / monMap.k)
                    }
                  }
                }
              }
              Rectangle {   // the "i" bubble: under the row, over the rows below
                visible: !!rowItem.r.hint && st.hintRow === rowItem.index && rowItem.focused
                anchors { right: parent.right; rightMargin: 8; top: parent.bottom; topMargin: 2 }
                width: Math.min(parent.width - 20, Math.round(380 * Theme.scale)); height: hintText.implicitHeight + 16
                radius: Theme.radiusInner; color: Theme.surface
                border.width: 1; border.color: Theme.line
                Label { id: hintText; anchors { fill: parent; margins: 8 } text: rowItem.r.hint || ""; textFormat: Text.StyledText; wrapMode: Text.WordWrap
                        color: Theme.text; font.pixelSize: Math.round(11 * Theme.scale) }
              }
              Row {   // controls on the right
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                Chip {   // "i": a short explanation of this setting (row field hint)
                  visible: !!rowItem.r.hint
                  anchors.verticalCenter: parent.verticalCenter
                  text: "i"; focusedChip: false
                  onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; st.hintRow = st.hintRow === rowItem.index ? -1 : rowItem.index }
                }
                Chip {   // listen: plays the event's current sound
                  visible: !!rowItem.r.play
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u25B6"
                  onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; rowItem.r.play() }
                }
                Switch {   // choice On / Off
                  visible: st.isSwitch(rowItem.r)
                  anchors.verticalCenter: parent.verticalCenter
                  on: st.isSwitch(rowItem.r) && st.switchOn(rowItem.r)
                  focusedChip: st.keyNav && rowItem.focused
                  onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; st.toggleSwitch(rowItem.r) }
                }
                Rectangle {   // choice: 2-3 values as one joined control
                  visible: rowItem.r.type === "choice" && !rowItem.r.preview && !st.isSwitch(rowItem.r)
                  anchors.verticalCenter: parent.verticalCenter
                  width: segRow.implicitWidth; height: 24; radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge
                  Rectangle {   // the selection: one accent pill that springs to the picked segment
                    id: segPill
                    readonly property int idx: rowItem.r.type === "choice" && rowItem.r.options ? rowItem.r.options.findIndex(o => String(rowItem.r.get()) === String(o[0])) : -1
                    readonly property Item seg: (segRow.implicitWidth, idx >= 0 ? segRep.itemAt(idx) : null)
                    property bool live: false   // no flight on first show
                    Component.onCompleted: Qt.callLater(() => live = true)
                    visible: !!seg
                    x: seg ? seg.x + 2 : 0; y: 2; width: seg ? seg.width - 4 : 0; height: parent.height - 4
                    radius: Theme.radiusCtl; color: Theme.accent
                    Behavior on x { enabled: segPill.live; NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
                    Behavior on width { enabled: segPill.live; NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
                  }
                  Row {
                    id: segRow
                    Repeater {
                      id: segRep
                      model: rowItem.r.type === "choice" && !rowItem.r.preview && !st.isSwitch(rowItem.r) ? rowItem.r.options : []
                      Seg {
                        required property var modelData
                        required property int index
                        text: modelData[1]; on: String(rowItem.r.get()) === String(modelData[0]); focusedChip: st.keyNav && rowItem.focused && st.cursor === index
                        onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; rowItem.r.set(modelData[0]) }
                      }
                    }
                  }
                }
                Repeater {   // choice with a picture (settings_spec 3.1): tiling / floating schematics
                  model: rowItem.r.preview === "env" ? rowItem.r.options : []
                  MouseArea {
                    id: pv
                    required property var modelData
                    required property int index
                    readonly property bool on: String(rowItem.r.get()) === String(modelData[0])
                    readonly property bool hot: st.keyNav && rowItem.focused && st.cursor === index
                    width: 120; height: 84; cursorShape: Qt.PointingHandCursor
                    onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; rowItem.r.set(modelData[0]) }
                    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: pv.on ? Theme.tint : "transparent"   // Nothing: outlined preview card
                                border.width: pv.on || pv.hot ? 2 : 1; border.color: pv.on ? Theme.accent : pv.hot ? Theme.ring : Theme.edge }
                    Item {
                      anchors { fill: parent; margins: 8; bottomMargin: 22 }
                      Repeater {
                        model: pv.modelData[0] === "tiling" ? [[0, 0, 0.56, 1], [0.6, 0, 0.4, 0.47], [0.6, 0.53, 0.4, 0.47]]
                                                            : [[0.02, 0.18, 0.55, 0.62], [0.4, 0.34, 0.58, 0.62], [0.2, 0, 0.42, 0.4]]
                        Rectangle {
                          required property var modelData
                          x: modelData[0] * parent.width; y: modelData[1] * parent.height
                          width: modelData[2] * parent.width; height: modelData[3] * parent.height
                          radius: 3; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
                          border.width: 1; border.color: pv.on ? Theme.accent : Theme.line
                        }
                      }
                    }
                    Label { anchors { bottom: parent.bottom; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                            text: pv.modelData[1]; color: pv.on ? Theme.accent : Theme.text; font.pixelSize: Math.round(11 * Theme.scale) }
                  }
                }
                Repeater {   // action: buttons
                  model: rowItem.r.type === "action" ? rowItem.r.buttons : []
                  Chip {
                    required property var modelData
                    required property int index
                    text: modelData[0]; focusedChip: st.keyNav && rowItem.focused && st.chip === index
                    onClicked: modelData[1]()
                  }
                }
                MouseArea {   // cycle: a drop-down button (list opens under it)
                  id: ddBtn
                  visible: rowItem.r.type === "cycle"
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(Math.round(300 * Theme.scale), Math.max(110, (rowItem.r.type === "cycle" ? Math.max(...rowItem.r.options.map(o => ddFm.advanceWidth(String(o[1])))) : ddText.implicitWidth) + 40)); height: 24   // capped: a long option text (xkb names) must not grow the button over the label
                  FontMetrics { id: ddFm; font: ddText.font }
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  opacity: st.ddShown && st.ddLast === rowItem.index ? 0 : 1   // it is the list now (the list folds back into its place)
                  onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; st.openDd(rowItem.index, ddBtn) }
                  Connections { target: st; function onDdReqChanged() { if (st.ddReqRow === rowItem.index && rowItem.r.type === "cycle") st.openDd(rowItem.index, ddBtn) } }
                  Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; border.width: 1; border.color: Theme.edge   // Nothing: outlined dropdown
                              color: st.ddRow === rowItem.index || ddBtn.containsMouse || (st.keyNav && rowItem.focused) ? Theme.fillHover : "transparent"
                              Behavior on color { ColorAnimation { duration: Motion.duration } } }
                  Label {
                    id: ddText
                    anchors { left: parent.left; leftMargin: 10; right: caret.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    color: Theme.text
                    text: rowItem.r.type !== "cycle" ? "" : ((rowItem.r.options.find(o => String(o[0]) === String(rowItem.r.get())) || [0, String(rowItem.r.get())])[1])
                  }
                  Icon { id: caret; name: "caret-up-down"; color: Theme.dim; anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } }
                }
                KnoblessSlider {   // slider: flat bar + value, no thumb
                  visible: rowItem.r.type === "slider"
                  width: Math.round(220 * Theme.scale); anchors.verticalCenter: parent.verticalCenter
                  steps: rowItem.r.type === "slider" ? rowItem.r.steps : []
                  unit: rowItem.r.unit || ""
                  format: rowItem.r.format || null
                  value: rowItem.r.type === "slider" ? Number(rowItem.r.get()) : 0
                  highlighted: rowItem.focused
                  activeFocusOnTab: false   // keys come from the launcher input via handleKey
                  onMoved: v => { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; rowItem.r.set(v) }
                }
                InputField {   // input: one-line text, Enter applies, Esc cancels
                  id: fld
                  visible: rowItem.r.type === "input"
                  width: Math.round(220 * Theme.scale); height: 24; anchors.verticalCenter: parent.verticalCenter
                  value: rowItem.r.type === "input" ? String(rowItem.r.get()) : ""
                  secret: !!rowItem.r.secret
                  placeholder: rowItem.r.placeholder || ""
                  validate: rowItem.r.validate || null
                  onAccepted: t => rowItem.r.set(t)
                  onDone: st.refocus()
                  onEditingChanged: if (editing) { st.keyNav = false; st.pane = "page"; st.row = rowItem.index }
                  Connections { target: st; function onInputReqChanged() { if (st.row === rowItem.index && st.pane === "page" && rowItem.r.type === "input") fld.start() } }
                  MouseArea { anchors.fill: parent; enabled: !fld.editing; cursorShape: Qt.IBeamCursor; onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; fld.start() } }
                }
                Label { visible: rowItem.r.type === "picker"; text: rowItem.r.type === "picker" ? rowItem.r.value() : ""; color: Theme.dim
                        font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale); rightPadding: 4 }   // Nothing: values in mono caps
                Icon { visible: rowItem.r.type === "picker"; name: "caret-right"; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                Item {   // meter: live mic level (settings_spec 4.1) - PwNodePeakMonitor only runs while this page is open
                  visible: rowItem.r.type === "meter"
                  width: Math.round(220 * Theme.scale); height: Math.round(10 * Theme.scale); anchors.verticalCenter: parent.verticalCenter
                  PwNodePeakMonitor { id: mic; node: Audio.source; enabled: rowItem.r.type === "meter" && st.soundOpen }
                  Rectangle {
                    anchors.fill: parent; radius: height / 2; color: Theme.line
                    Rectangle { width: parent.width * Math.max(0, Math.min(1, mic.peak)); height: parent.height; radius: parent.radius
                                color: Theme.accent; Behavior on width { NumberAnimation { duration: Motion.fit(Motion.fast * 0.65) } } }
                  }
                }
                Label { visible: rowItem.r.type === "info"; text: rowItem.r.type === "info" ? (typeof rowItem.r.value === "function" ? rowItem.r.value() : rowItem.r.value) : ""; color: Theme.dim; font.family: Theme.label
                       width: Math.min(implicitWidth, rowItem.width - 220); elide: Text.ElideRight }
                Item {   // pin toggle: shown on pinned rows always, on others while hovered / focused
                  visible: !!rowItem.r.pin
                  width: pinIcon.width + 8; height: parent.height
                  readonly property bool on: !!rowItem.r.pin && st.isPinned(rowItem.r.pin)
                  opacity: on || rowItem.focused || pinArea.containsMouse || rowHover.hovered ? 1 : 0
                  Icon { id: pinIcon; anchors.centerIn: parent; name: parent.on ? "push-pin" : "push-pin-simple"; color: parent.on ? Theme.accent : Theme.dim }
                  MouseArea { id: pinArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                              onClicked: st.togglePin(rowItem.r.pin) }
                }
                MouseArea {   // hotkey: the combination drawn as key caps; a click records a new one
                  id: hkCaps
                  visible: rowItem.r.type === "hotkey"
                  readonly property bool capt: st.capturing === rowItem.r.keys
                  width: capRow.width; height: 24
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { st.keyNav = false; st.pane = "page"; st.row = rowItem.index; if (rowItem.r.removed) st.restoreBind(rowItem.r.keys); else st.startCapture(rowItem.r.keys) }
                  Row {
                    id: capRow; spacing: 4; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                      model: hkCaps.capt ? ["Press keys…"] : rowItem.r.type !== "hotkey" ? [] : rowItem.r.removed ? ["Removed"] : (rowItem.r.keys || "").split(/\s*\+\s*/).filter(x => x)
                      Rectangle {
                        required property string modelData
                        height: 22; width: capText.implicitWidth + 14; radius: Theme.radiusCtl
                        color: hkCaps.capt ? Theme.accent : Theme.fill; border.width: 1; border.color: hkCaps.capt ? Theme.accent : Theme.edge
                        Text { id: capText; anchors.centerIn: parent; text: parent.modelData; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale)
                               color: hkCaps.capt ? Theme.accentInk : rowItem.r.removed ? Theme.dim : Theme.text }
                      }
                    }
                  }
                }
                Chip {   // remove the bind (kept in the file behind //off, Restore brings it back)
                  visible: rowItem.r.type === "hotkey" && !rowItem.r.removed
                  text: "Remove"
                  onClicked: st.setRebind(rowItem.r.keys, "")
                }
                Chip {
                  visible: rowItem.r.type === "hotkey" && rowItem.r.removed
                  text: "Restore"
                  onClicked: st.restoreBind(rowItem.r.keys)
                }
                Chip {   // hotkey changed from the factory one: back to it (Backspace does the same)
                  visible: rowItem.r.type === "hotkey" && !!rowItem.r.def
                  text: "Reset"
                  onClicked: st.setRebind(rowItem.r.keys, rowItem.r.def)
                }
              }
            }
          }
        }
      }
    }
  }

  MouseArea {   // drop-down list: click outside closes
    id: ddLayer
    anchors.fill: parent; z: 50
    readonly property bool open: st.ddRow >= 0
    visible: open || ddCard.opacity > 0 || st.ddUnfold
    enabled: open
    onClicked: st.closeDd()
    Item {   // the button itself unfolds into the list (spring) and folds back into it on close
      id: ddCard
      readonly property real fullH: Math.min(st.ddOpts.length * 24, 240)
      x: st.ddUnfold ? st.ddX : st.ddB.x
      y: st.ddUnfold ? st.ddY : st.ddB.y
      width: st.ddUnfold ? st.ddW : st.ddB.width
      height: st.ddUnfold ? fullH : st.ddB.height
      opacity: st.ddKeep ? 1 : 0   // a flag, not a Behavior: Behavior.enabled / ddLayer.open were read stale on open and the close pause ran then
      clip: false
      Behavior on x { enabled: ddLayer.visible && !st.ddJump; NumberAnimation { duration: st.ddUnfold ? Motion.unfold : Motion.dropClose; easing.type: Motion.type; easing.bezierCurve: st.ddUnfold ? Motion.unfoldCurve : Motion.curve } }
      Behavior on y { enabled: ddLayer.visible && !st.ddJump; NumberAnimation { duration: st.ddUnfold ? Motion.unfold : Motion.dropClose; easing.type: Motion.type; easing.bezierCurve: st.ddUnfold ? Motion.unfoldCurve : Motion.curve } }
      Behavior on width { enabled: ddLayer.visible && !st.ddJump; NumberAnimation { duration: st.ddUnfold ? Motion.unfold : Motion.dropClose; easing.type: Motion.type; easing.bezierCurve: st.ddUnfold ? Motion.unfoldCurve : Motion.curve } }
      Behavior on height { enabled: ddLayer.visible && !st.ddJump; NumberAnimation { duration: st.ddUnfold ? Motion.unfold : Motion.dropClose; easing.type: Motion.type; easing.bezierCurve: st.ddUnfold ? Motion.unfoldCurve : Motion.curve } }
      Repeater {   // shadow: three widening, fading rims under the card (only once it unfolds: the button has none)
        model: 3
        Rectangle {
          required property int index
          opacity: st.ddUnfold ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Motion.dropOpen } }
          anchors { fill: parent; margins: -(index + 1) * 2; topMargin: -(index + 1) * 2 + 3 }
          radius: Theme.radiusCard + (index + 1) * 2
          color: "transparent"; border.width: 2; border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.03)
        }
      }
      // the button's own look, made solid: surface under the button fill, same corners, no frame
      // at the start it IS the button (its see-through fill only); the solid base thickens as it unfolds, thins as it folds
      Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.surface
                  opacity: st.ddUnfold ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: st.ddUnfold ? Motion.unfold : Motion.dropClose; easing.type: Easing.InOutQuad } } }
      Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover }
      Item {   // the list at its full size, cut by the unfolding card (no reflow while it grows)
        anchors.fill: parent; clip: true
        opacity: ddLayer.open ? 1 : 0   // no fade in: the current row already shows the button's own text in its place
      ListView {
        id: ddList
        x: st.ddX - ddCard.x; y: st.ddY - ddCard.y; width: st.ddW; height: ddCard.fullH
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: st.ddOpts
        currentIndex: st.ddIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        onModelChanged: Qt.callLater(() => positionViewAtIndex(st.ddIndex, ListView.Center))   // opens on the current value
        highlightFollowsCurrentItem: false
        Rectangle {   // the hover / keys wash glides from item to item
          z: -1; width: ddList.width; height: 24; radius: Theme.radiusInner; color: Theme.fillHover
          y: ddList.currentItem ? ddList.currentItem.y - ddList.contentY : 0
          visible: ddLayer.open && !!ddList.currentItem
          Behavior on y { NumberAnimation { duration: Motion.duration * 1.3; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
        }
        delegate: MouseArea {
          id: ddItem
          required property var modelData
          required property int index
          readonly property bool chosen: (r => !!r && String(r.get()) === String(modelData[0]))(st.ddRow >= 0 ? st.rows[st.ddRow] : null)
          width: ddList.width; height: 24; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onEntered: if (ddLayer.open) st.ddIndex = index
          onClicked: { st.ddIndex = index; st.applyDd() }
          Label { anchors { left: parent.left; leftMargin: 10; right: ddCheck.left; rightMargin: 4; verticalCenter: parent.verticalCenter }   // = the button's label
                  elide: Text.ElideRight
                  text: ddItem.modelData[1]; color: Theme.text }
          Icon { id: ddCheck; name: "check"; color: Theme.accent; opacity: ddItem.chosen ? 1 : 0   // where the button's caret was
                 anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } }
        }
      }
      }
    }
  }
}
