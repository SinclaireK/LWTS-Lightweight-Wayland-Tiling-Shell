// Compositor settings for niri: LWTS writes ~/.config/niri/lwts.kdl from settings.toml (Prefs) and the theme (Theme),
// niri live-reloads it (config.kdl has `include "lwts.kdl"` last, so these values win). Replaces every
// `hyprctl eval hl.config(...)` / `hyprctl reload` of the Hyprland version: Settings change a pref, call apply(), done.
// Nothing here runs in the background: apply() is debounced and writes one small file.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/niri/lwts.kdl"
  signal applied()

  function apply() { debounce.restart() }
  property string current: ""   // what is on disk: an unchanged file is not rewritten, so niri does not reload for nothing
  Timer { id: debounce; interval: 200; onTriggered: { const t = root.kdl(); if (t !== root.current) { root.current = t; out.setText(t); root.applied() } } }
  FileView { id: out; path: root.path; printErrors: false; onLoaded: root.current = text() }
  Connections { target: Theme; function onDataChanged() { root.apply() } }   // new palette -> new border colours
  Connections { target: Session; function onGameChanged() { root.apply() } }
  Connections { target: Prefs; function onVChanged() { root.apply() } }   // any settings.toml change (also from the old engine) -> regenerate, written only if it differs
  Component.onCompleted: apply()
  Connections { target: Motion; function onSmoothChanged() { root.apply() } }
  Binding {   // niri reports refresh in mHz; the fastest screen decides (springs are one setting for all outputs)
    target: Motion; property: "hz"
    value: Math.max(0, ...Object.values(Compositor.outputs).map(o => o.modes && o.modes[o.current_mode] ? o.modes[o.current_mode].refresh_rate / 1000 : 0))
  }

  // ---- helpers ----
  function hex(c, a) {   // QML colour -> "#rrggbbaa"
    const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
    return "#" + h(c.r) + h(c.g) + h(c.b) + h(a === undefined ? c.a : a);
  }
  function over(c, a) { const b = Theme.surface; return Qt.rgba(c.r * a + b.r * (1 - a), c.g * a + b.g * (1 - a), c.b * a + b.b * (1 - a), 1) }   // opaque look of colour c at alpha a over the surface
  function q(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' }
  // Lite (Session.game) overrides what the game_* switches name
  function pref(k, d) {
    if (Session.game) {
      if (k === "motion" && Session.gameOn("game_animations")) return "off";
      if (k === "blur" && Session.gameOn("game_blur")) return "off";
      if (k === "round_windows" && Session.gameOn("game_rounding")) return 0;
    }
    if (k === "round_windows") return Prefs.radii[3];   // presets own these (Settings -> Look)
    if (k === "gaps") return Prefs.gapsPx[0];
    if (k === "blur") return Prefs.transparency === "solid" ? "off" : (v => ["light", "normal", "strong"].includes(v) ? v : "normal")(Prefs.get("blur", "normal"));
    return Prefs.get(k, d);
  }
  function bool(k, d) { return pref(k, d) === true || pref(k, d) === "true" }

  // blur levels (same names as Hyprland's: off | light | normal | strong | custom) -> niri's dual-kawase passes / offset
  readonly property var blurLevels: ({ off: null, light: [2, 2], normal: [3, 3], strong: [4, 4] })
  function blurBlock() {
    const lvl = pref("blur", "normal");
    const b = lvl === "custom" ? [Math.max(1, Math.min(6, Number(pref("blur_layers", 3)))), Math.max(1, Math.min(10, Number(pref("blur_radius", 3))))] : blurLevels[lvl];
    if (!b) return "blur {\n    off\n}\n";
    return "blur {\n    passes " + b[0] + "\n    offset " + b[1] + "\n    noise " + Number(pref("blur_noise", 0.03)) + "\n    saturation " + (1 + Number(pref("blur_vibrancy", 0.15))) + "\n}\n";
  }

  function layoutBlock() {
    const gaps = Number(pref("gaps", 12)), bw = Math.max(1, Number(pref("border_width", 2)));   // never off: the screenshot tool finds windows by their borders
    let s = "layout {\n    gaps " + gaps + "\n    focus-ring {\n        off\n    }\n";
    if (bw > 0) {
      const a = Number(pref("border_opacity", 0.19));
      s += "    border {\n        on\n        width " + bw + "\n        active-color " + q(hex(over(Theme.accent, Math.max(a, 0.6)), 1)) + "\n"
         + "        inactive-color " + q(hex(over(Theme.text, a), 1)) + "\n        urgent-color " + q(hex(Theme.red, 1)) + "\n    }\n";
    } else s += "    border {\n        off\n    }\n";
    return s + "}\n";
  }

  function inputBlock() {
    const num = k => Number(pref(k, 0));
    let kb = "    keyboard {\n        xkb {\n            layout " + q(pref("kb_layout", "us,ua,ru")) + "\n";
    const kbo = pref("kb_options", "grp:alt_shift_toggle,compose:ralt");
    if (kbo) kb += "            options " + q(kbo) + "\n";
    kb += "        }\n        repeat-delay " + Number(pref("kb_repeat_delay", 250)) + "\n        repeat-rate " + Number(pref("kb_repeat_rate", 50)) + "\n";
    if (bool("kb_numlock", false)) kb += "        numlock\n";
    kb += "    }\n";
    const flat = pref("mouse_accel", "flat") === "flat";
    // DPI compensation (Settings -> Input -> Mouse): 800 DPI is the reference feel; at another DPI the flat factor (1 + speed) is scaled by 800/DPI so the pointer keeps its speed
    const dpi = Math.max(100, Number(pref("mouse_dpi", 800)) || 800);
    const mspeed = flat ? Math.round(Math.max(-1, Math.min(1, (1 + num("mouse_speed")) * 800 / dpi - 1)) * 1000) / 1000 : num("mouse_speed");
    let mouse = "    mouse {\n        accel-profile " + q(flat ? "flat" : "adaptive") + "\n        accel-speed " + mspeed + "\n";
    if (bool("natural_scroll", false)) mouse += "        natural-scroll\n";
    if (bool("left_handed", false)) mouse += "        left-handed\n";
    mouse += "        scroll-factor " + Number(pref("scroll_factor", 1)) + "\n";
    const sb = pref("scroll_btn", "off");
    if (sb !== "off") mouse += "        scroll-method \"on-button-down\"\n        scroll-button " + (sb === "extra" ? 276 : 275) + "\n";
    mouse += "    }\n";
    // touchpad + TrackPoint (Settings -> Input); the defaults equal the old fixed block (tap, natural scroll, dwt)
    let tp = "    touchpad {\n";
    if (bool("tp_tap", true)) tp += "        tap\n";
    if (bool("tp_natural", true)) tp += "        natural-scroll\n";
    if (bool("tp_dwt", true)) tp += "        dwt\n";
    if (bool("tp_middle", false)) tp += "        middle-emulation\n";
    if (bool("tp_off_with_mouse", false)) tp += "        disabled-on-external-mouse\n";
    tp += "        accel-profile " + q(pref("tp_accel", "adaptive") === "flat" ? "flat" : "adaptive") + "\n        accel-speed " + num("tp_speed") + "\n";
    tp += "        click-method " + q(pref("tp_click", "clickfinger") === "areas" ? "button-areas" : "clickfinger") + "\n    }\n";
    let pt = "    trackpoint {\n        accel-profile " + q(pref("pt_accel", "flat") === "adaptive" ? "adaptive" : "flat") + "\n        accel-speed " + num("pt_speed") + "\n";
    if (bool("pt_middle_scroll", true)) pt += "        scroll-method \"on-button-down\"\n";
    pt += "    }\n";
    return "input {\n" + kb + mouse + tp + pt + "}\n";
  }

  function cursorBlock() {
    return "cursor {\n    xcursor-theme " + q(pref("cursor_theme", "breeze_cursors")) + "\n    xcursor-size " + Number(pref("cursor_size", 24)) + "\n"
         + (bool("cursor_hide_typing", false) ? "    hide-when-typing\n" : "") + "}\n";
  }

  // motion: on | off. Springs follow the screen (Motion.smooth): high refresh = soft bounce, 60 Hz = critically damped and stiffer
  function animationsBlock() {
    if (pref("motion", "on") === "off") return "animations {\n    off\n}\n";
    const sp = Motion.smooth ? "spring damping-ratio=0.65 stiffness=" + Math.round(600 / (Motion.slowmo * Motion.slowmo)) + " epsilon=0.0001" : "spring damping-ratio=1.0 stiffness=" + Math.round(900 / (Motion.slowmo * Motion.slowmo)) + " epsilon=0.0001";
    return "animations {\n    workspace-switch {\n        " + sp + "\n    }\n    horizontal-view-movement {\n        " + sp
         + "\n    }\n    window-movement {\n        " + sp + "\n    }\n    window-resize {\n        " + sp + "\n    }\n}\n";
  }

  // glass: blur behind windows (with their rounded corners); the shell's layers set their own blur region
  function rulesBlock() {
    const r = Number(pref("round_windows", 6));
    const on = pref("blur", "normal") !== "off";
    let s = "window-rule {\n    geometry-corner-radius " + r + "\n    clip-to-geometry true\n" + (on ? "    background-effect {\n        blur true\n    }\n" : "") + "}\n";
    // the shell's layers draw their own blur shape (BackgroundEffect.blurRegion); niri only picks xray (wallpaper) vs live
    if (on)
      s += "layer-rule {\n    match namespace=\"^(waybar|lwts-.*)$\"\n    background-effect {\n        xray " + (pref("blur_xray", false) === true) + "\n    }\n}\n";
    // overview backdrop: the gradient surface (overlays/WallpaperBackdrop.qml) is drawn only behind the workspaces
    s += "layer-rule {\n    match namespace=\"^(lwts-wallpaper-blur|awww-daemonbackdrop)$\"\n    place-within-backdrop true\n}\n";
    return s;
  }

  // monitors: dsp_<NAME>_{mode,scale,position,transform,vrr,off} keys that the Displays settings page writes (name with - as _)
  function outputsBlock() {
    let s = "";
    for (const m of System.monitors) {
      const k = "dsp_" + m.name.replace(/-/g, "_") + "_";
      const mode = pref(k + "mode", ""), scale = pref(k + "scale", ""), pos = pref(k + "position", ""), tr = pref(k + "transform", ""), vrr = pref(k + "vrr", "");
      if (!mode && !scale && !pos && !tr && vrr === "" && !bool(k + "off", false)) continue;
      s += "output " + q(m.name) + " {\n";
      if (bool(k + "off", false)) { s += "    off\n}\n"; continue }
      if (mode) s += "    mode " + q(String(mode).replace(/Hz$/, "")) + "\n";
      if (scale) s += "    scale " + Number(scale) + "\n";
      if (tr && tr !== "Normal" && tr !== "0") s += "    transform " + q(tr) + "\n";
      const p = String(pos).match(/^(-?\d+)x(-?\d+)$/);
      if (p) s += "    position x=" + p[1] + " y=" + p[2] + "\n";
      if (vrr === true || vrr === "true" || vrr === 1 || vrr === "1") s += "    variable-refresh-rate\n";
      else if (vrr === 2 || vrr === "2") s += "    variable-refresh-rate on-demand=true\n";
      s += "}\n";
    }
    return s;
  }

  function kdl() {
    return "// Generated by LWTS (quickshell services/NiriConf.qml) from ~/.config/themes/settings.toml. Do not edit: changes are overwritten.\n"
         + layoutBlock() + inputBlock() + cursorBlock() + animationsBlock() + blurBlock() + rulesBlock() + outputsBlock();
  }
}
