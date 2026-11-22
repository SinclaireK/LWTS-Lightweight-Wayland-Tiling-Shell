// Data widgets: user-defined live items for the launcher (text row or tile). Definitions in ~/.config/themes/widgets.json:
//   [{ "id": "weather", "label": "Weather", "icon": "cloud-sun", "cmd": ["sh", "$P/weather.sh", "Kharkiv"], "every": 60,
//      "act": ["cmd", ...] (Enter; optional), "open": "path or url" (Enter; optional) }]
// "$P" = this module's presets folder. The command prints JSON {value, sub, on, alert, progress} or plain text (line 1 value, line 2 sub).
// A widget only runs while it is placed in the launcher (qs_tiles has "x_<id>"). File missing = the presets below are written.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  readonly property string presets: Quickshell.shellDir + "/modules/dataw/presets"
  readonly property string path: Quickshell.env("HOME") + "/.config/themes/widgets.json"
  property var defs: []
  property var values: ({})   // id -> { value, sub, on, alert, progress }
  readonly property var defaults: [
    { id: "cal", label: "Schedule", icon: "calendar-blank", cmd: ["luajit", "$P/calendar.lua", ""], every: 60 },   // put an .ics / CIST CSV link or a file in the last field
    { id: "weather", label: "Weather", icon: "cloud-sun", cmd: ["sh", "$P/weather.sh", ""], every: 1800 },
  ]
  function expand(a) { return a.map(s => String(s).replace("$P", presets).replace(/^~(?=\/)/, Quickshell.env("HOME"))) }
  function set(id, v) { const o = Object.assign({}, values); o[id] = v; values = o }
  function parse(text) {
    const t = text.trim();
    try { const j = JSON.parse(t); if (j && typeof j === "object") return j } catch (e) {}
    const l = t.split("\n"); return { value: l[0] || "", sub: l.slice(1).join(" ").trim() };
  }
  function act(id) {
    const d = defs.find(x => x.id === id); if (!d) return;
    if (d.act) Quickshell.execDetached(expand(d.act));
    else if (d.open) Quickshell.execDetached(["xdg-open", expand([d.open])[0]]);
    refresh(id);
  }
  signal refresh(string id)
  // shortcuts: a tile that opens a link / an app ({ id, label, icon, open }); Settings -> Features -> Widgets adds them
  readonly property var brands: [["tiktok", "tiktok-logo"], ["youtu", "youtube-logo"], ["github", "github-logo"], ["t.me", "telegram-logo"], ["telegram", "telegram-logo"],
                                 ["discord", "discord-logo"], ["twitch", "twitch-logo"], ["reddit", "reddit-logo"], ["spotify", "spotify-logo"], ["instagram", "instagram-logo"],
                                 ["x.com", "x-logo"], ["twitter", "x-logo"], ["steam", "steam-logo"], ["google", "google-logo"]]
  function iconFor(link) { const l = String(link).toLowerCase(); const b = brands.find(x => l.includes(x[0])); return b ? b[1] : /^[a-z]+:\/\//.test(l) ? "link" : "app-window" }
  function hostOf(link) { const m = String(link).match(/^[a-z]+:\/\/(?:www\.)?([^/?#]+)/i); return m ? m[1] : String(link).split(" ")[0] }
  property string newName: ""
  property string newLink: ""
  function save(list) { file.setText(JSON.stringify(list, null, 2) + "\n") }
  function addShortcut() {
    const link = newLink.trim(); if (!link) return;
    const name = newName.trim() || hostOf(link);
    let id = "s_" + name.toLowerCase().replace(/[^a-z0-9]+/g, "").slice(0, 16) || "s_link";
    while (defs.some(d => d.id === id)) id += "1";
    const d = { id, label: name, icon: iconFor(link) };
    if (/^[a-z]+:\/\//i.test(link)) d.open = link; else d.act = ["sh", "-c", link];   // a link opens in its app, anything else runs as a command
    save(defs.concat([d])); newName = ""; newLink = "";
  }
  function remove(id) { save(defs.filter(d => d.id !== id)) }
  function edit() { Quickshell.execDetached(["xdg-open", path]) }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { const d = JSON.parse(text()); if (Array.isArray(d)) root.defs = d.filter(x => x && x.id && (x.cmd || x.open || x.act)) } catch (e) { console.warn("widgets.json:", e) } }
    onLoadFailed: err => { if (err === FileViewError.FileNotFound) setText(JSON.stringify(root.defaults, null, 2) + "\n") }
  }

  Variants {
    model: root.defs.filter(d => !!d.cmd)   // shortcuts (only "open" / "act") have nothing to run
    Scope {
      id: w
      required property var modelData
      readonly property string tid: "x_" + modelData.id
      readonly property bool active: Prefs.get("qs_tiles", []).includes(tid)
      Process {
        id: proc
        command: root.expand(w.modelData.cmd)
        stdout: StdioCollector { onStreamFinished: root.set(w.modelData.id, root.parse(text)) }
      }
      Timer {
        interval: Math.max(5, Number(w.modelData.every) || 60) * 1000
        running: w.active; repeat: true; triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
      }
      Connections { target: root; function onRefresh(id) { if (id === w.modelData.id && !proc.running) proc.running = true } }
    }
  }
}
