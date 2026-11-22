// Optional modules (philosophy v2: base + modules). A module is a folder <shell>/modules/<id>/ with manifest.json (id, name,
// version, contract = 1 and, all optional: service / settings / tiles = file names):
//   service  - Service.qml: background code (a QtObject or Scope), created once at start
//   settings - Settings.qml: a QtObject with `section` (a settings category id) and `rows` (same rows as SettingsNew builds)
//   tiles    - Tiles.qml: a QtObject with `defs` (Quick settings tiles, same shape as Tiles.all)
//   panels   - Panels.qml: a QtObject with `files` (bar pop-up panels: id -> file of the module; the item may set keepOpen / dropWidth)
//   widgets  - Widgets.qml: a QtObject with `defs` (desktop widgets: id, name, file, sizes, needs; file relative to the module; see services/Desk.qml)
//   palettes - Palettes.qml: a QtObject with `list` (theme picker entries id/label/colors); the .toml files in palettes/ are copied by lwts-module
// Module code may import qs.core / qs.services but the base never imports a module. scripts/lwts-module (list, install,
// remove) manages the folder; the shell reads it once at start, so a reload applies a change.
// NB: the Quickshell scanner looks for `pragma Singleton` before the first opening brace - none in this header.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  readonly property int contract: 1
  readonly property string dir: Quickshell.shellDir + "/modules"
  property var list: []        // manifests found, with .path
  property var pageObjs: []    // loaded Settings.qml objects
  property var tileObjs: []    // loaded Tiles.qml objects
  property var paletteObjs: [] // loaded Palettes.qml objects
  property var panelObjs: []   // { path, files } of loaded Panels.qml
  property var barObjs: []     // loaded Bar.qml objects: `items` = live activities (a running timer...) drawn as bar pills
  readonly property var activities: barObjs.reduce((a, o) => a.concat(o.items), [])
  property string videoUrl: ""   // VideoWall.qml of the "livewall" module (live wallpapers); "" = none, a video file is then not drawn
  property string openSection: ""   // id of the Settings category on screen ("" = Settings closed / searching): a module refreshes its data while its category is open
  property var ctx: ({})       // the shell's own objects for modules: bar, popups, launcher (set by shell.qml)
  function panelUrl(id) {
    for (const p of panelObjs) if (p.files[id]) return "file://" + p.path + "/" + p.files[id];
    return "";
  }
  readonly property var palettes: paletteObjs.reduce((a, o) => a.concat(o.list), [])
  readonly property var tiles: tilesOf(tileObjs)   // id -> tile definition, merged into Tiles.all
  function tilesOf(objs) { const t = {}; for (const o of objs) Object.assign(t, o.defs); return t }

  // ---- Settings -> Features -> Modules (the base owns this page: it is how a module gets in) ----
  property var available: []     // from sources.toml: { id, name, version, installed }
  property bool needsReload: false
  readonly property string tool: Quickshell.shellDir + "/scripts/lwts-module"
  function refresh() { avail.running = false; avail.running = true }
  // built into the system: always loaded, not listed under Modules, their settings live in the base categories
  readonly property var core: ["clipboard", "notes", "caffeine", "powertimer", "daynight", "hardware", "printers", "tools", "modes", "games"]
  function enabled(id) { return core.indexOf(id) >= 0 || (Prefs.get("modules_off", []) || []).indexOf(id) < 0 }   // a turned-off module stays installed but is not loaded
  function setEnabled(id, on) {
    const l = (Prefs.get("modules_off", []) || []).filter(x => x !== id);
    if (!on) l.push(id);
    Prefs.set("modules_off", l); needsReload = true;
  }
  function act(verb, id) { Quickshell.execDetached([tool].concat(verb === "install" ? ["install", "-y", id] : ["remove", id])); needsReload = true; later.restart() }
  Timer { id: later; interval: 900; onTriggered: root.refresh() }
  Process {
    id: avail
    command: [root.tool, "json"]
    stdout: StdioCollector { onStreamFinished: { try { root.available = JSON.parse(text) } catch (e) { root.available = [] } } }
  }
  function pageRows() {
    const rows = [{ type: "header", label: "Optional modules" },
      { type: "info", label: "Installed", value: String(list.filter(x => core.indexOf(x.id) < 0).length) },
      { type: "info", label: "Warning", value: "a module is code with your access; install only from sources you trust" }];
    for (const m of available.filter(x => core.indexOf(x.id) < 0)) {
      const d = m.id + " v" + m.version;
      if (m.installed)   // a segmented switch: On / Off, and Remove (kept in modules/.removed)
        rows.push({ type: "choice", label: m.name, desc: d, options: [["on", "On"], ["off", "Off"], ["remove", "Remove"]],
                    get: () => root.enabled(m.id) ? "on" : "off",
                    set: v => v === "remove" ? root.act("remove", m.id) : root.setEnabled(m.id, v === "on") });
      else rows.push({ type: "action", label: m.name, desc: d + " · not installed", buttons: [["Install", () => root.act("install", m.id)]] });
    }
    if (!available.length) rows.push({ type: "info", label: "No modules found", value: "add a folder in ~/.config/lwts/sources.toml" });
    if (needsReload) rows.push({ type: "action", label: "Apply changes", desc: "The shell reads modules at start", buttons: [["Reload shell", () => Quickshell.reload(false)]] });
    return rows;
  }
  Component.onCompleted: refresh()

  // the settings categories with the modules' rows appended (a category without a module stays as it was)
  function extend(sections) {
    const extra = {};
    for (const p of pageObjs) (extra[p.section] = extra[p.section] || []).push(...p.rows);
    for (const p of pageObjs) Object.keys(p.extra || {}).forEach(k => { extra[k] = (extra[k] || []).concat(p.extra[k]) });   // optional rows for more categories
    let out = sections.map(s => extra[s.id] && s.rows ? Object.assign({}, s, { rows: s.rows.concat(extra[s.id]) }) : s);
    const mods = { id: "modules", icon: "puzzle-piece", label: "Modules", rows: pageRows() }, sys = out.findIndex(s => s.id === "system");   // install / on / off / remove: its own category, before System
    out = sys < 0 ? out.concat([mods]) : out.slice(0, sys).concat([mods], out.slice(sys));
    for (const p of pageObjs) {   // a module may bring a whole category: sectionDef { id, icon, label, before }
      const d = p.sectionDef;
      if (!d || out.some(s => s.id === d.id)) continue;
      const at = out.findIndex(s => s.id === d.before), sec = { id: d.id, icon: d.icon, label: d.label, rows: extra[d.id] };
      out = at < 0 ? out.concat([sec]) : out.slice(0, at).concat([sec], out.slice(at));
    }
    return out;
  }

  function load(m) {
    const make = (file, keep) => {
      const c = Qt.createComponent("file://" + m.path + "/" + file);
      if (c.status !== Component.Ready) { console.warn("module " + m.id + ": " + file + ": " + c.errorString()); return null }
      const o = c.createObject(root); if (o && keep) keep(o); return o;
    };
    if (m.service) make(m.service);
    if (m.settings) make(m.settings, o => root.pageObjs = root.pageObjs.concat([o]));
    if (m.tiles) make(m.tiles, o => root.tileObjs = root.tileObjs.concat([o]));
    if (m.panels) make(m.panels, o => root.panelObjs = root.panelObjs.concat([{ path: m.path, files: o.files }]));
    if (m.bar) make(m.bar, o => root.barObjs = root.barObjs.concat([o]));
    if (m.videowall) root.videoUrl = "file://" + m.path + "/" + m.videowall;
    if (m.widgets) make(m.widgets, o => Desk.moduleDefs = Desk.moduleDefs.concat(o.defs.map(d => Object.assign({}, d, { file: "file://" + m.path + "/" + d.file }))));
    if (m.palettes) make(m.palettes, o => root.paletteObjs = root.paletteObjs.concat([o]));
  }

  Process {   // one line per module: "<path>\t<manifest json on one line>"
    id: scan
    running: true
    command: ["sh", "-c", 'for f in "$1"/*/manifest.json; do [ -f "$f" ] && { printf "%s\\t" "$(dirname "$f")"; tr -d "\\n" < "$f"; echo; }; done', "sh", root.dir]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = [];
        for (const line of text.split("\n")) {
          const i = line.indexOf("\t"); if (i < 0) continue;
          try { const m = JSON.parse(line.slice(i + 1)); m.path = line.slice(0, i); if (m.id && m.contract === root.contract) found.push(m); else console.warn("module skipped (contract): " + line.slice(0, i)) }
          catch (e) { console.warn("module manifest unreadable: " + line.slice(0, i)) }
        }
        root.list = found; found.filter(m => root.enabled(m.id)).forEach(root.load);
      }
    }
  }
}
