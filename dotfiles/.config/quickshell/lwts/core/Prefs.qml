// User preferences: ~/.config/themes/settings.toml, parsed here natively and live (no Lua / Python).
// Any QML binds to it: `radius: Prefs.rounding`, `visible: Prefs.module("clock")`.
// set(key, value) rewrites one line of the file; the FileView watch then updates every binding.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  readonly property string path: Quickshell.env("HOME") + "/.config/themes/settings.toml"
  property var v: ({})
  property bool ready: false   // settings.toml read: the bar waits for it, or it opens with the defaults (gap 12) and keeps them
  function get(key, fallback) { return v[key] !== undefined && v[key] !== "" ? v[key] : fallback }

  // geometry
  // look presets (Settings -> Look): rounding square|soft|round, gaps none|compact|spacious; old numeric keys pick the start value
  readonly property string roundingPreset: get("rounding_preset", (r => r === 0 ? "square" : r >= 10 ? "round" : "soft")(Number(get("rounding", 6))))
  readonly property var radii: ({ square: [0, 0, 0, 0], soft: [5, 5, 3, 5], round: [15, 12, 9, 15] })[roundingPreset] || [5, 5, 3, 5]   // outer, card, inner, windows
  readonly property int rounding: radii[0]
  readonly property string gapPreset: get("gap_preset", (g => g === 0 ? "none" : g <= 6 ? "compact" : "spacious")(Number(get("bar_gap", 12))))
  readonly property var gapsPx: ({ none: [0, 0], compact: [6, 6], spacious: [12, 12] })[gapPreset] || [12, 12]   // windows, bar
  readonly property string barPosition: get("bar_position", "top")        // top | bottom
  readonly property int barHeight: Number(get("bar_height_px", 22))
  // transparency layers (LWTS_SPEC 1): L0 window/overlay, L1 sidebar, L2 group cards
  // transparency preset (Settings -> Look): glass | soft | solid; explicit opacity_l* keys still win
  readonly property string transparency: get("transparency", "glass")
  readonly property bool blurOn: transparency !== "solid" && get("blur", "normal") !== "off"   // no blur region asked of niri when opaque
  readonly property var tp: ({ glass: [0.74, 0.50, 0.70], soft: [0.88, 0.70, 0.85], solid: [1, 1, 1] })[transparency] || [0.74, 0.50, 0.70]
  readonly property real opacityL0: Number(get("opacity_l0", tp[0]))
  readonly property real opacityL1: Number(get("opacity_l1", tp[1]))
  readonly property real opacityL2: Number(get("opacity_l2", tp[2]))
  readonly property string motion: get("motion", "on")          // on | off (old spring / calm = on)
  readonly property int blur: Number(get("blur_px", 24))
  // fonts: empty = the theme's font (Theme.font)
  readonly property string font: get("font", "")
  readonly property string monoFont: get("mono_font", "JetBrainsMono Nerd Font")
  // modules switched off in Settings -> Bar -> Modules
  readonly property var hidden: get("waybar_hidden", [])
  function module(name) { return hidden.indexOf(name) < 0 }

  // TOML subset used by settings.toml: key = "string" | number | true/false | ["a", "b"]
  function parse(text) {
    const out = {};
    for (const line of text.split("\n")) {
      const m = line.match(/^\s*([\w.]+)\s*=\s*(.*?)\s*$/);
      if (!m) continue;
      out[m[1]] = value(m[2]);
    }
    return out;
  }
  function value(s) {
    if (s.startsWith('"')) return s.slice(1, s.indexOf('"', 1));
    if (s.startsWith("[")) return (s.match(/"[^"]*"|[^\s,\[\]]+/g) || []).map(x => value(x));
    if (s === "true" || s === "false") return s === "true";
    const n = Number(s.replace(/\s*#.*$/, ""));
    return isNaN(n) ? s : n;
  }
  function encode(val) {
    if (Array.isArray(val)) return "[" + val.map(encode).join(", ") + "]";
    if (typeof val === "string") return '"' + val + '"';
    return String(val);
  }
  function set(key, val) { const o = {}; o[key] = val; setMany(o) }
  function setMany(obj) {   // several keys in one write (separate set() calls in one tick would read a stale file)
    const cur = file.text();
    if (!root.ready || cur.trim() === "") { console.warn("Prefs: settings.toml not loaded or empty, write skipped"); return }   // never rewrite the file from an empty read
    prev.setText(cur);   // the version being replaced goes to settings.toml.prev first
    const lines = cur.split("\n");
    for (const key in obj) {
      const line = key + " = " + encode(obj[key]);
      const i = lines.findIndex(l => l.match(new RegExp("^\\s*" + key + "\\s*=")));
      if (i >= 0) lines[i] = line;
      else lines.splice(lines[lines.length - 1] === "" ? lines.length - 1 : lines.length, 0, line);
    }
    file.setText(lines.join("\n"));
    const v = Object.assign({}, root.v); for (const k in obj) v[k] = obj[k]; root.v = v;   // bindings update at once
  }

  FileView { id: prev; path: root.path + ".prev"; atomicWrites: true; preload: false }

  FileView {
    id: file
    path: root.path
    atomicWrites: true   // temp file + rename: a crash mid-write cannot leave a half file
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.v = root.parse(text()); root.ready = true }
  }
}
