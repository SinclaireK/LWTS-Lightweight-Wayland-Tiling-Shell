// Desktop widgets engine (state). Placement list in settings.toml: desk_widgets = ["clockweather:DP-2:0:0:4:2", ...] = id:output:x:y:w:h
// (x y w h in grid cells; id = widget id, "#2" suffix for a second copy). The windows live in desktop/DeskHost.qml: ONE Bottom layer
// surface per output that has something to show (a window costs ~16 MB, widgets inside it almost nothing; measured 2026-11-19, ai/plans.md),
// click-through everywhere except the widget rectangles.
// Cost rules: no widget placed = no window, no timer. Lite (Session.game) removes the windows except widgets marked "keep in Lite"
// (desk_keep = ["id"]). `awake` is the gate every widget timer / process binds to: false under a fullscreen window and while locked.
// Widgets from modules: manifest key "widgets" = Widgets.qml with `defs` = list of (id, name, file, sizes [[w,h]..], needs [..]) objects, see Modules.qml.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  readonly property int cell: 64          // px of one grid cell
  readonly property int gap: 8            // px between cells
  // The wallpaper has a dot lattice: step 18 px, first dot at 9 px from the output's corner (measured on DP-2). The grid origin sits on a dot and
  // every pitch is a multiple of 18 (cell 64 + gap 8 = 72 = 4 dots), so widget and icon cells line up with the dots; items are inset by gap / 2.
  readonly property int dotStep: 18
  readonly property int dotOff: 9
  function dotAtOrAfter(v) { return dotOff + dotStep * Math.ceil((v - dotOff) / dotStep) }
  readonly property int ox: dotAtOrAfter(24)
  readonly property int oy: dotAtOrAfter(Prefs.barPosition === "top" ? Prefs.barHeight + 40 : 24)
  readonly property int inset: gap / 2
  function px(n) { return n * cell + (n - 1) * gap }
  function pos(n) { return n * (cell + gap) }

  property var moduleDefs: []             // widgets of installed modules (Modules.load)
  readonly property var defs: [
    { id: "clockweather", name: "Clock + weather", file: "file://" + Quickshell.shellDir + "/desktop/ClockWeather.qml", sizes: [[4, 2], [2, 2]], needs: ["weather"] },
  ].concat(moduleDefs)
  function def(id) { return defs.find(d => d.id === id) || null }

  function parse(s) {
    const a = String(s).split(":"); if (a.length < 6) return null;
    const p = { id: a[0], wid: a[0].split("#")[0], mon: a[1], x: Number(a[2]), y: Number(a[3]), w: Number(a[4]), h: Number(a[5]) };
    return [p.x, p.y, p.w, p.h].some(isNaN) ? null : p;
  }
  function enc(p) { return [p.id, p.mon, p.x, p.y, p.w, p.h].join(":") }
  readonly property bool enabled: Prefs.get("desk", true) !== false
  // per-instance options: desk_opts = ["id;key=value;key=value"] (when = "work": the widget is shown only in Work mode)
  function optsOf(id) {
    const o = {}, line = (Prefs.get("desk_opts", []) || []).find(l => String(l).split(";")[0] === id);
    if (line) String(line).split(";").slice(1).forEach(kv => { const i = kv.indexOf("="); if (i > 0) o[kv.slice(0, i)] = kv.slice(i + 1) });
    return o;
  }
  function optLine(id, o) { const kv = Object.keys(o).filter(k => o[k] !== "" && o[k] !== undefined).map(k => k + "=" + String(o[k]).replace(/[;"]/g, "")); return kv.length ? id + ";" + kv.join(";") : "" }
  readonly property var placed: (Prefs.get("desk_widgets", []) || []).map(parse).filter(p => p && def(p.wid)).map(p => Object.assign(p, { opts: optsOf(p.id) }))
  readonly property var keepIds: Prefs.get("desk_keep", []) || []
  // Work mode (desktop menu): adds the file tools to the menu; widgets marked when=work appear only while it is on
  readonly property bool work: Prefs.get("desk_work", false) === true
  // ---- desktop icons (Work mode, desktop/DeskIconLayer.qml): paths and names are ARGUMENTS of the commands, never part of a script text ----
  property var selection: []                 // selected paths
  function isSel(path) { return selection.includes(path) }
  readonly property string iconSize: Prefs.get("desk_icon_size", "medium")   // small | medium | large
  readonly property int iconPitch: ({ small: 54, medium: 72, large: 90 })[iconSize] || 72   // 3 / 4 / 5 dots
  readonly property int iconPx: iconPitch - gap
  readonly property bool iconColored: Prefs.get("desk_icon_style", "color") !== "mono"   // Papirus as it is, or the monochrome icon engine
  readonly property bool iconsLocked: Prefs.get("desk_icons_lock", false) === true
  readonly property string iconSort: Prefs.get("desk_sort", "name")   // name | type | date (the auto order)
  // the icons show on ONE output: desk_icons_mon, default the biggest one
  readonly property string iconMon: String(Prefs.get("desk_icons_mon", "")) || Quickshell.screens.reduce((b, s) => !b || s.width * s.height > b.width * b.height ? s : b, null)?.name || ""
  // saved cells: desk_icon_pos = ["<url-encoded name>|col|row"]; a file without one takes the first free cell
  readonly property var iconPos: {
    const m = {};
    for (const l of (Prefs.get("desk_icon_pos", []) || [])) { const a = String(l).split("|"); if (a.length === 3) m[decodeURIComponent(a[0])] = [Number(a[1]), Number(a[2])] }
    return m;
  }
  function savePositions(map) { Prefs.set("desk_icon_pos", Object.keys(map).map(n => encodeURIComponent(n) + "|" + map[n][0] + "|" + map[n][1])) }
  function arrangeBy(sort) { Prefs.setMany({ desk_sort: sort, desk_icon_pos: [] }) }
  // the Trash icon (a special entry of the icon layer)
  readonly property string trashPath: "trash:///"
  property bool trashFull: false             // set by the layer (watches ~/.local/share/Trash/files)
  function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]) }
  function newLink(target) { Quickshell.execDetached(["luajit", Quickshell.shellDir + "/scripts/desk-link.lua", dir, target]) }
  function trashMenuItems() {
    return [
      { label: "Open", icon: "folder-open", act: () => openEntry(trashPath) },
      { label: "Empty trash", icon: "trash", off: !trashFull, sub: [{ label: "Delete forever", act: emptyTrash }] },
    ];
  }
  function openEntry(path) { Quickshell.execDetached(["sh", "-c", 'case "$1" in *.desktop) exec gio launch "$1";; *) exec xdg-open "$1";; esac', "sh", path]) }
  function openSelection() { selection.slice(0, 12).forEach(openEntry) }
  function renameEntry(path, name) {
    Quickshell.execDetached(["sh", "-c", 'n=$(printf %s "$2" | tr / _); [ -n "$n" ] && mv -n -- "$1" "$(dirname "$1")/$n"', "sh", path, name]);
  }
  function trashSelection() { const l = selection.filter(p => p !== trashPath); if (l.length) Quickshell.execDetached(["gio", "trash"].concat(l)); selection = [] }   // to the trash, restorable
  function clipSelection(mode) { const l = selection.filter(p => p !== trashPath); if (l.length) Quickshell.execDetached(["luajit", Quickshell.shellDir + "/scripts/desk-clip.lua", mode].concat(l)) }
  // what the menu knows about the first selected file (scripts/desk-info.lua): type, size, apps that open it
  property var info: ({ path: "", mime: "", size: 0, mtime: 0, items: -1, apps: [] })
  function fetchInfo() {
    if (selection.length !== 1) { info = { path: "", mime: "", size: 0, mtime: 0, items: -1, apps: [] }; return }
    infoProc.path = selection[0]; infoProc.command = ["luajit", Quickshell.shellDir + "/scripts/desk-info.lua", selection[0]]; infoProc.running = false; infoProc.running = true;
  }
  Process {
    id: infoProc
    property string path: ""
    stdout: StdioCollector {
      onStreamFinished: {
        const o = { path: infoProc.path, mime: "", size: 0, mtime: 0, items: -1, apps: [] };
        for (const l of text.split("\n")) {
          const f = l.split("\t");
          if (f[0] === "type") o.mime = f[1]; else if (f[0] === "size") o.size = Number(f[1]); else if (f[0] === "mtime") o.mtime = Number(f[1]);
          else if (f[0] === "items") o.items = Number(f[1]); else if (f[0] === "app" && f.length >= 5) o.apps.push({ id: f[1], name: f[2], file: f[3], def: f[4] === "1" });
        }
        root.info = o;
      }
    }
  }
  function sizeText(b) { return b < 1024 ? b + " B" : b < 1048576 ? (b / 1024).toFixed(1) + " KB" : b < 1073741824 ? (b / 1048576).toFixed(1) + " MB" : (b / 1073741824).toFixed(2) + " GB" }
  function homeShort(p) { const h = Quickshell.env("HOME"); return p.startsWith(h) ? "~" + p.slice(h.length) : p }
  function parentOf(path) { return path.replace(/\/[^/]*\/?$/, "") || "/" }
  function openWith(appFile, path) { Quickshell.execDetached(["gio", "launch", appFile, path]) }
  function copyPaths() { Quickshell.execDetached(["wl-copy", "--", selection.join("\n")]) }
  function showInFolder() { Quickshell.execDetached(["xdg-open", parentOf(selection[0])]) }
  function terminalAt(dir) { Quickshell.execDetached(["alacritty", "--working-directory", dir]) }
  // compress the selection next to it (scripts/desk-compress.lua; paths are arguments)
  function compress(kind) { Quickshell.execDetached(["luajit", Quickshell.shellDir + "/scripts/desk-compress.lua", kind].concat(selection)) }
  function itemMenuItems() {
    if (selection.length === 1 && selection[0] === trashPath) return trashMenuItems();
    const n = selection.length, one = n === 1 ? selection[0] : "", tail = n > 1 ? " (" + n + ")" : "";
    const i = info.path === one ? info : null;
    const isDir = !!i && i.mime === "inode/directory";
    const with_ = !i ? [{ label: "...", info: true }] : i.apps.length ? i.apps.map(a => ({ label: a.name, hint: a.def ? "DEFAULT" : "", act: () => openWith(a.file, one) })) : [{ label: "No applications", info: true }];
    const props = !i ? [{ label: "...", info: true }] : [
      { label: "Type  " + i.mime, info: true },
      { label: isDir ? "Items  " + i.items : "Size  " + sizeText(i.size), info: true },
      { label: "Modified  " + Qt.formatDateTime(new Date(i.mtime * 1000), "yyyy-MM-dd HH:mm"), info: true },
      { label: "In  " + homeShort(parentOf(one)), info: true },
    ];
    return [
      { strip: [
        { icon: "scissors", act: () => clipSelection("cut") },
        { icon: "copy", act: () => clipSelection("copy") },
        { icon: "pencil-simple", off: n !== 1, ask: n === 1 ? { title: "Rename", text: one.split("/").pop(), accept: t => renameEntry(one, t) } : undefined },
        { icon: "trash", act: trashSelection },
      ] },
      { label: "Open" + tail, act: openSelection },
      { label: "Open with", off: n !== 1, sub: with_ },
      { label: "Properties", off: n !== 1, sub: props },
      { sep: true },
      { label: "More", sub: [
        { label: "Compress", sub: [{ label: ".zip", act: () => compress("zip") }, { label: ".tar.gz", act: () => compress("tar.gz") }] },
        { label: "Copy path", act: copyPaths },
        { label: "Show in folder", act: showInFolder },
        { label: "Terminal here", act: () => terminalAt(isDir ? one : parentOf(selection[0])) },
      ] },
    ];
  }
  function openTerminal() { Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cd "$1" && exec alacritty', "sh", dir]) }
  // Paste: what the clipboard holds becomes a file in the desktop folder (scripts/desk-paste.lua; the folder is an argument)
  function paste() { Quickshell.execDetached(["luajit", Quickshell.shellDir + "/scripts/desk-paste.lua", dir]) }
  function toggleWork() { Prefs.set("desk_work", !work) }
  function visible(p) { return (p.opts.when !== "work" || work) && (!Session.game || keepIds.includes(p.id)) }

  function on(mon) { return placed.filter(p => p.mon === mon) }
  // what is on screen: everything normally, only the "keep in Lite" ones while Lite (Session.game) is on
  function shownList(mon) { return !enabled ? [] : on(mon).filter(visible) }
  readonly property bool anyShown: !enabled ? false : placed.some(visible)
  // timers / processes of widgets run only while this is true (a surface under a fullscreen window gets no frames anyway)
  readonly property bool awake: anyShown && !Lock.locked && !OsdState.fullscreenFocused
  function needs(n) { return placed.some(p => (def(p.wid).needs || []).includes(n)) }

  // ---- desktop context menu (desktop/DeskHost.qml, widgets/UiMenu.qml) ----
  readonly property bool menuOn: enabled && Prefs.get("desk_menu", true) !== false && !Session.game
  readonly property string dir: String(Prefs.get("desk_dir", "")) || Quickshell.env("HOME") + "/Desktop"
  // new file / folder in the desktop folder: the name is an ARGUMENT of the script (never part of its text); "/" becomes "_", a taken name gets " 2"
  function create(kind, name) {
    Quickshell.execDetached(["sh", "-c", 'd="$1"; n=$(printf %s "$3" | tr / _); [ -n "$n" ] || exit 1; mkdir -p "$d" || exit 1; p="$d/$n"; i=2; while [ -e "$p" ]; do p="$d/$n $i"; i=$((i+1)); done; if [ "$2" = dir ]; then mkdir "$p"; else : > "$p"; fi', "sh", dir, kind, name]);
  }
  signal testMenu(string mon, int x, int y, bool onIcon)   // ipc `desk menu`: open the menu without a click
  function nameOf(p) { return (def(p.wid) || {}).name + (p.opts.folder ? " " + p.opts.folder.split("/").filter(x => x).pop() : p.id.includes("#") ? " " + p.id.split("#")[1] : "") }
  function cellAt(px, py) { return [Math.max(0, Math.round((px - ox) / (cell + gap))), Math.max(0, Math.round((py - oy) / (cell + gap)))] }
  function menuItems(mon, px, py, done) {   // px py = the click, in surface pixels
    const c = cellAt(px, py), here = on(mon), items = [];
    const ask = (title, kind) => ({ title, accept: t => create(kind, t) });
    // Work mode changes the menu: creating files / folders and opening the folder are work tools, the plain desktop menu has none of them
    if (work) {
      items.push({ label: "New", icon: "plus", sub: [
        { label: "File", icon: "file", ask: ask("New file", "file") },
        { label: "Folder", icon: "folder", ask: ask("New folder", "dir") },
        { label: "Link", icon: "link", ask: { title: "Link to a path or URL", text: "", accept: t => newLink(t) } },
      ] });
      items.push({ label: "Paste", icon: "clipboard", act: paste });
      items.push({ label: "Open terminal", icon: "terminal-window", act: openTerminal });
      const arrange = (id, label) => ({ label, on: iconSort === id, act: () => arrangeBy(id), keep: true });
      items.push({ label: "Icons", icon: "eye", sub: [
        arrange("name", "Arrange by name"), arrange("type", "Arrange by type"), arrange("date", "Arrange by date"),
        { sep: true },
        { label: "Colored icons", on: iconColored, act: () => Prefs.set("desk_icon_style", iconColored ? "mono" : "color"), keep: true },
        { sep: true },
        { label: "Small icons", on: iconSize === "small", act: () => Prefs.set("desk_icon_size", "small"), keep: true },
        { label: "Medium icons", on: iconSize === "medium", act: () => Prefs.set("desk_icon_size", "medium"), keep: true },
        { label: "Large icons", on: iconSize === "large", act: () => Prefs.set("desk_icon_size", "large"), keep: true },
        { sep: true },
        { label: "Lock in place", on: iconsLocked, act: () => Prefs.set("desk_icons_lock", !iconsLocked), keep: true },
      ] });
      items.push({ sep: true });
    }
    items.push({ label: "Work mode", on: work, act: toggleWork });
    items.push({ sep: true });
    const w = [];
    w.push({ label: "Add here", icon: "plus", sub: defs.map(d => ({ label: d.name, act: () => add(d.id, mon, c[0], c[1]) })) });
    if (here.length) {
      w.push({ label: "Move here", icon: "squares-four", sub: here.map(p => ({ label: nameOf(p), act: () => move(p.id, c[0], c[1]) })) });
      w.push({ label: "Remove", icon: "x", sub: here.map(p => ({ label: nameOf(p), act: () => remove(p.id) })) });
    }
    items.push({ label: "Widgets", icon: "squares-four", sub: w });
    items.push({ sep: true });
    items.push({ label: "Wallpaper", icon: "image", act: () => Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "pick", "wallpaper"]) });
    items.push({ label: "Settings", icon: "gear-six", act: () => Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "settings", "0"]) });
    return items;
  }

  function optsList(list) { return list.map(p => optLine(p.id, p.opts || {})).filter(l => l !== "") }
  function save(list) { Prefs.setMany({ desk_widgets: list.map(enc), desk_opts: optsList(list) }) }
  function add(wid, mon, x, y, opts) {
    const d = def(wid); if (!d) return;
    let id = wid, n = 1; while (placed.some(p => p.id === id)) id = wid + "#" + (++n);
    save(placed.concat([{ id, wid, mon, x, y, w: d.sizes[0][0], h: d.sizes[0][1], opts: opts || {} }]));
  }
  function remove(id) { save(placed.filter(p => p.id !== id)) }
  function setOpt(id, k, v) { save(placed.map(p => p.id === id ? Object.assign({}, p, { opts: Object.assign({}, p.opts, { [k]: v }) }) : p)) }
  function move(id, x, y) { save(placed.map(p => p.id === id ? Object.assign({}, p, { x, y }) : p)) }
  function resize(id, w, h) { save(placed.map(p => p.id === id ? Object.assign({}, p, { w, h }) : p)) }

  // shared data source: weather (one process for all widgets that need it; 30 min; only while awake)
  property var weather: ({ value: "--", sub: "", icon: "" })
  Process {
    id: wproc
    command: ["sh", Quickshell.shellDir + "/modules/dataw/presets/weather.sh", String(Prefs.get("desk_city", ""))]
    stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(text); if (j && j.value) root.weather = j } catch (e) {} } }
  }
  Timer {
    interval: 1800000; repeat: true; triggeredOnStart: true
    running: root.awake && root.needs("weather")
    onTriggered: if (!wproc.running) wproc.running = true
  }
}
