// Colours and fonts of the current theme, live: ~/.cache/themes/current.json is rewritten by theme.py.
// Geometry comes from Prefs (one rounding for everything); game mode turns every layer fully opaque.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property var data: ({})
  function c(name, fallback) {
    const v = data.colors && data.colors[name];
    return v ? v["default"].color : fallback;
  }

  // palette
  property color surface: "#282828"   // glides to the new theme (see glide below)
  property color container: "#3c3836"   // glides to the new theme (see glide below)
  property color text: "#d4be98"   // glides to the new theme (see glide below)
  property color dim: "#a89984"   // glides to the new theme (see glide below)
  property color accent: "#d8a657"   // glides to the new theme (see glide below)
  readonly property color accentInk: (accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114) > 0.55 ? "#141414" : "#f5f5f0"   // from the real accent (a palette may override accent but not matugen's on_primary: black-on-black)   // not animated: "onX" would read as a signal handler
  property color red: "#ea6962"   // glides to the new theme (see glide below)
  property color yellow: "#d8a657"   // glides to the new theme (see glide below)
  property color green: "#a9b665"   // glides to the new theme (see glide below)

  // Palette colours glide to the new theme instead of jumping (derived colours follow); the first load and game mode are instant.
  property bool _loaded: false
  ColorAnimation { id: g_surface; target: root; property: "surface"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_container; target: root; property: "container"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_text; target: root; property: "text"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_dim; target: root; property: "dim"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_accent; target: root; property: "accent"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_red; target: root; property: "red"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_yellow; target: root; property: "yellow"; duration: 380; easing.type: Easing.InOutQuad }
  ColorAnimation { id: g_green; target: root; property: "green"; duration: 380; easing.type: Easing.InOutQuad }
  function glide() {
    const instant = !_loaded || game;
    _loaded = true;
    g_surface.stop(); if (instant) root.surface = c("surface", "#282828"); else { g_surface.to = c("surface", "#282828"); g_surface.start() }
    g_container.stop(); if (instant) root.container = c("surface_container_high", "#3c3836"); else { g_container.to = c("surface_container_high", "#3c3836"); g_container.start() }
    g_text.stop(); if (instant) root.text = c("on_surface", "#d4be98"); else { g_text.to = c("on_surface", "#d4be98"); g_text.start() }
    g_dim.stop(); if (instant) root.dim = c("on_surface_variant", "#a89984"); else { g_dim.to = c("on_surface_variant", "#a89984"); g_dim.start() }
    g_accent.stop(); if (instant) root.accent = c("primary", "#d8a657"); else { g_accent.to = c("primary", "#d8a657"); g_accent.start() }
    g_red.stop(); if (instant) root.red = data.term ? data.term.red : "#ea6962"; else { g_red.to = data.term ? data.term.red : "#ea6962"; g_red.start() }
    g_yellow.stop(); if (instant) root.yellow = data.term ? data.term.yellow : "#d8a657"; else { g_yellow.to = data.term ? data.term.yellow : "#d8a657"; g_yellow.start() }
    g_green.stop(); if (instant) root.green = data.term ? data.term.green : "#a9b665"; else { g_green.to = data.term ? data.term.green : "#a9b665"; g_green.start() }
  }
  readonly property color line: Qt.rgba(text.r, text.g, text.b, 0.12)     // 1px borders
  readonly property color tint: Qt.rgba(accent.r, accent.g, accent.b, 0.18) // "on" / focus fill
  // controls are filled, not outlined: resting fill, hover fill, keyboard focus ring (borders only for focus)
  readonly property color fill: Qt.rgba(text.r, text.g, text.b, 0.07)
  readonly property color fillHover: Qt.rgba(text.r, text.g, text.b, 0.12)
  readonly property color ring: Qt.rgba(accent.r, accent.g, accent.b, 0.7)
  readonly property color edge: Qt.rgba(text.r, text.g, text.b, 0.24)   // Nothing: controls are outlined (1 px) on the black field, not grey-filled
  // focus ring on an accent-filled control: the accent pushed lighter (or darker if the accent is already light), never white
  readonly property color ringOnAccent: (accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114) > 0.6 ? Qt.darker(accent, 1.6) : Qt.lighter(accent, 1.6)

  // geometry
  readonly property int radius: Prefs.radii[0]        // windows, bar, drops
  readonly property int radiusCard: Prefs.radii[1]    // group cards, notifications
  readonly property int radiusInner: Prefs.radii[2]   // buttons, rows, tiles, fields
  readonly property int radiusCtl: Prefs.roundingPreset === "square" ? 0 : 6   // Nothing: buttons, chips, segments, toggles are slightly rounded rectangles (6 px), no pills
  readonly property int gap: Prefs.gapsPx[1]   // bar/drops/dock margin (Settings -> Geometry -> Bar gaps)
  readonly property bool barGapRounded: Prefs.get("bar_gap_rounded", false)

  // fonts
  readonly property string font: Prefs.font || (data.ui ? data.ui.font : "Inter")
  readonly property string mono: Prefs.monoFont
  readonly property string label: "Geist Mono"   // Nothing: every label / button / caption is mono capitals
  readonly property string dot: "Ndot57Caps"   // community copy of Nothing Ndot57 Caps (~/.local/share/fonts/rice/dot/Ndot57Caps-Regular.otf, Cyrillic ok, NOT in git: no licence). Free fallback: "LWTS Dot" (Doto OFL, no Cyrillic)   // Nothing style, always on: dot-matrix numerals (clock, big numbers); Qt falls back to the UI font if Doto is missing
  // icon fonts (Phosphor, ~/.local/share/fonts/phosphor): loaded by file, the "-Fill" family name does not match
  readonly property string icons: iconsLight.name   // Nothing: thin line icons (Phosphor Light, same glyph set as Regular)
  readonly property string iconsFill: iconsSolid.name
  readonly property string iconsBold: iconsHeavy.name
  // Phosphor has Regular and Bold: follow the UI font's own default weight (fontconfig: 80 regular, 200 bold, 210 extra bold ...)
  property string iconWeight: "regular"
  Process {
    id: weightProbe
    command: ["fc-match", "-f", "%{weight}", root.font]
    running: true
    stdout: StdioCollector { onStreamFinished: root.iconWeight = Number(text) >= 180 ? "bold" : "regular" }
  }
  onFontChanged: weightProbe.running = true
  FontLoader { id: iconsHeavy; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/phosphor/Phosphor-Bold.ttf" }
  readonly property string iconsMs: ""   // Material Symbols switched OFF (user: "not Google design"); thin Phosphor Light lines are the Nothing look. Was: iconsMaterial.name
  FontLoader { id: iconsMaterial; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/material/MaterialSymbolsOutlined.ttf" }
  FontLoader { id: iconsLight; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/phosphor/Phosphor-Light.ttf" }
  FontLoader { id: iconsRegular; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/phosphor/Phosphor.ttf" }
  FontLoader { id: iconsSolid; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/phosphor/Phosphor-Fill.ttf" }
  readonly property real scale: data.ui ? Number(data.ui.size_pt) / 11 : 1
  readonly property string barFont: data.ui ? (data.ui.bar_font || data.ui.font) : font
  readonly property int barPx: data.ui ? Number(data.ui.bar_px) : 13

  // game mode (IPC bar.gameMode): solid layers, no motion, no OSD; flush: bar against the screen edges
  property bool game: false
  property bool playing: false   // a game is running (whatever game_* options say): no notification pop-ups, no OSD - they break tearing
  property bool lite: false   // Lite mode asked for a flush bar
  readonly property bool flush: lite || gap === 0   // bar against the screen edges, square, no frame
  readonly property real opacityL0: game ? 1 : Prefs.opacityL0
  readonly property real opacityL1: game ? 1 : Prefs.opacityL1
  readonly property real opacityL2: game ? 1 : Prefs.opacityL2

  FileView {
    path: Quickshell.env("HOME") + "/.cache/themes/current.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.data = JSON.parse(text()); root.glide() }
  }
}
