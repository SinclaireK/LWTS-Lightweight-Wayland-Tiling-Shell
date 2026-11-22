// Look actions for Settings: palette (theme.py), wallpaper, compositor keys that live in settings.toml (written to niri by NiriConf).
pragma Singleton
import QtQuick
import Quickshell
import qs.core

Singleton {
  id: root
  signal hyprTouched()   // the compositor applied something: it may have taken the keyboard from an open drop (name kept: Launcher listens)
  readonly property string home: Quickshell.env("HOME")
  readonly property string walls: home + "/Pictures/Wallpapers"
  readonly property string currentPalette: Theme.data.theme ? Theme.data.theme.id : ""
  readonly property string currentWall: Theme.data.image || ""

  // trial set; the full list comes after the settings are done (LWTS_SPEC 8)
  // default + 5 characters, each dark and light (LWTS_SPEC 8); + paired families only (light + dark): dark first, then light
  readonly property var palettes: basePalettes.concat(Modules.palettes)   // + the palettes of installed modules (services/Modules.qml)
  readonly property var basePalettes: [
    // own gem palettes only; the old ones are in ~/.config/themes/palettes-archive/old-2026-11-17/
    { id: "malachite-dark", label: "Malachite Dark", colors: ["#060c08","#e3eae5","#54cc8e"], ansi: ["#f38c8a","#79c37c","#c7ad45","#76b1fc","#da90d4","#15c5cd"] },
    { id: "malachite-light", label: "Malachite Light", colors: ["#eef6f1","#16211a","#006d42"], ansi: ["#a23c3f","#23762c","#756203","#2463ae","#8c4287","#0a7176"] },
    { id: "sapphire-dark", label: "Sapphire Dark", colors: ["#080a0f","#e4e8ef","#72a3fe"], ansi: ["#f38c8a","#79c37c","#c7ad45","#76b1fc","#da90d4","#15c5cd"] },
    { id: "sapphire-light", label: "Sapphire Light", colors: ["#f0f4fa","#191e28","#2554b1"], ansi: ["#a23c3f","#23762c","#756203","#2463ae","#8c4287","#0a7176"] },
    { id: "garnet-dark", label: "Garnet Dark", colors: ["#0f0808","#eee5e5","#ef7179"], ansi: ["#f38c8a","#79c37c","#c7ad45","#76b1fc","#da90d4","#15c5cd"] },
    { id: "garnet-light", label: "Garnet Light", colors: ["#faf1f1","#271a1a","#a22236"], ansi: ["#a23c3f","#23762c","#756203","#2463ae","#8c4287","#0a7176"] },
    { id: "amber-dark", label: "Amber Dark", colors: ["#0d0905","#ece7e1","#f5ae4b"], ansi: ["#f38c8a","#79c37c","#c7ad45","#76b1fc","#da90d4","#15c5cd"] },
    { id: "amber-light", label: "Amber Light", colors: ["#f8f2ec","#241d14","#885703"], ansi: ["#a23c3f","#23762c","#756203","#2463ae","#8c4287","#0a7176"] },
    { id: "amethyst-dark", label: "Amethyst Dark", colors: ["#0b090e","#e9e6ed","#c190f6"], ansi: ["#f38c8a","#79c37c","#c7ad45","#76b1fc","#da90d4","#15c5cd"] },
    { id: "amethyst-light", label: "Amethyst Light", colors: ["#f5f2f9","#201c26","#703ca0"], ansi: ["#a23c3f","#23762c","#756203","#2463ae","#8c4287","#0a7176"] },
  ]
  // settings that have side effects beyond saving (the old rofi/settings.lua engine, now native).
  // Callers pass "kind:arg": pp (power profile) | da (default app) | gs (game option toggle) | dm (dark mode)
  function engine(info) {
    hyprTouched();
    const k = info.indexOf(":"), kind = k < 0 ? info : info.slice(0, k), arg = k < 0 ? "" : info.slice(k + 1);
    if (kind === "pp") { if (arg.startsWith("set:")) Session.setProfile(arg.slice(4)); else Session.cycleProfile() }
    else if (kind === "dm" && arg === "toggle") toggleDark()
    else if (kind === "da") { const m = arg.match(/^(\d+):(.+)$/); if (m) setDefaultApp(Number(m[1]), m[2]) }
    else if (kind === "gs") Prefs.set(arg, Prefs.get(arg, true) === false)
  }
  readonly property var defaultApps: [   // [pref key, mime types]; the terminal has no mime type
    ["default_browser", ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"]],
    ["default_files", ["inode/directory"]], ["default_terminal", []] ]
  function setDefaultApp(i, id) {
    const d = defaultApps[i - 1]; if (!d) return;
    const file = id.endsWith(".desktop") ? id : id + ".desktop";
    // one type per call: this xdg-mime glues a list into one broken line
    for (const mime of d[1]) Quickshell.execDetached(["xdg-mime", "default", file, mime]);
    Prefs.set(d[0], id);
  }
  // dark <-> light: the day / night theme of the chosen family (defaults: Catppuccin)
  // the partner comes from the palette on screen (any path may have set it: picker, IPC, rofi), the saved pair is the fallback
  function toggleDark() {
    const pr = split ? null : pairs.find(x => x.includes(currentPalette));
    themeSet(pr ? pr[Session.dark ? 0 : 1] : Session.dark ? Prefs.get("day_theme", "garnet-light") : Prefs.get("night_theme", "garnet-dark"))
  }
  // keep the schedule (daynight.lua reads day_theme / night_theme) inside the family on screen
  onCurrentPaletteChanged: {
    const pr = split ? null : pairs.find(x => x.includes(currentPalette));
    if (pr && Prefs.ready && (Prefs.get("day_theme", "") !== pr[0] || Prefs.get("night_theme", "") !== pr[1]))
      Prefs.setMany({ day_theme: pr[0], night_theme: pr[1] });
  }
  readonly property var scheduleKeys: ["darkmode_mode", "darkmode_night", "darkmode_day", "nightlight_mode", "nightlight_night", "nightlight_day"]
  function oldSet(key, val) {
    Prefs.set(key, val);
    if (scheduleKeys.includes(key)) Quickshell.execDetached(["/usr/bin/luajit", home + "/.config/themes/daynight.lua", "apply"]);   // plans the next switch (systemd timer)
    else if (key === "font" || key === "mono" || key === "bar_font" || key === "ui_scale" || key === "icon_theme") retheme.restart();
    else if (key === "cursor_theme" || key === "cursor_size") {   // niri through NiriConf, GTK through gsettings, the rest through ~/.icons/default
      const t = Prefs.get("cursor_theme", "breeze_cursors"), sz = Prefs.get("cursor_size", 24);
      Quickshell.execDetached(["sh", "-c", 'mkdir -p ~/.icons/default && printf "[Icon Theme]\\nInherits=%s\\n" "$1" > ~/.icons/default/index.theme; '
        + 'gsettings set org.gnome.desktop.interface cursor-theme "$1"; gsettings set org.gnome.desktop.interface cursor-size "$2"', "sh", t, String(sz)]);
      NiriConf.apply();
    }
  }
  // input keys (Hyprland core/input.lua reads them from settings.toml): saved + applied live
  function setInput(obj) {
    Prefs.setMany(obj);
    const m = { kb_layout: "kb_layout", kb_options: "kb_options", mouse_speed: "sensitivity", mouse_dpi: "mouse_dpi", mouse_accel: "accel_profile",
                kb_repeat_delay: "repeat_delay", kb_repeat_rate: "repeat_rate", natural_scroll: "natural_scroll",
                scroll_factor: "scroll_factor", left_handed: "left_handed", kb_numlock: "numlock_by_default",
                tp_tap: "tp_tap", tp_natural: "tp_natural", tp_dwt: "tp_dwt", tp_middle: "tp_middle", tp_off_with_mouse: "tp_off_with_mouse",
                tp_accel: "tp_accel", tp_speed: "tp_speed", tp_click: "tp_click", pt_accel: "pt_accel", pt_speed: "pt_speed", pt_middle_scroll: "pt_middle_scroll" };
    const parts = [];
    for (const k in obj) if (m[k]) parts.push(m[k] + " = " + (typeof obj[k] === "string" ? '"' + obj[k] + '"' : obj[k]));
    if ("mouse_accel" in obj) parts.push("force_no_accel = " + (obj.mouse_accel === "flat"));
    if ("scroll_btn" in obj) parts.push("scroll_method = \"" + (obj.scroll_btn === "off" ? "" : "on_button_down") + "\"", "scroll_button = " + (obj.scroll_btn === "extra" ? 276 : 275));
    if (parts.length) { NiriConf.apply(); hyprTouched() }
  }
  function hyprReload() { reload.restart() }
  // displays (Settings -> Displays): applied at once by the old engine, kept only after Keep in the dialog
  // (overlays/DisplayConfirm.qml); after 12 s the engine reverts by itself
  property string displayPending: ""   // output name while a change waits for Keep
  property real displayDeadline: 0
  // niri changes a monitor at runtime with `niri msg output` (no config write); Keep then saves it into settings.toml (dsp_* keys,
  // NiriConf puts them in lwts.kdl), Revert / the 12 s timeout puts the old values back at runtime
  property var vrrUndo: null   // kept for the Settings page; niri needs no modeset hop for vrr
  property var displayUndo: null   // { name, vals: { mode, scale, transform, vrr } } of the monitor before the change
  function _outArgs(name, what, v) {
    if (what === "mode") return ["mode", String(v).replace(/Hz$/, "")];
    if (what === "scale") return ["scale", String(v)];
    if (what === "transform") return ["transform", ({ 0: "normal", 1: "90", 2: "180", 3: "270", 4: "flipped", 5: "flipped-90", 6: "flipped-180", 7: "flipped-270" })[v] || String(v)];
    if (what === "vrr") return String(v) === "2" ? ["vrr", "--on-demand", "on"] : ["vrr", (v === 1 || v === "1" || v === true || v === "on") ? "on" : "off"];
    if (what === "position") { const p = String(v).split("x"); return ["position", "set", p[0], p[1]] }
    if (what === "enabled") return [(v === 1 || v === "1" || v === true || v === "on") ? "on" : "off"];
    return null;
  }
  // 0 off, 1 always on, 2 on demand (only while a window with the vrr rule is shown); the saved choice wins over the live state
  function vrrMode(m) {
    const s = Prefs.get("dsp_" + m.name.replace(/-/g, "_") + "_vrr", "");
    return (s === "" || s === undefined) ? (m.vrr ? 1 : 0) : (s === true || s === "true" ? 1 : Number(s) || 0);
  }
  function setDisplay(name, what, v) {
    const m = System.monitors.find(x => x.name === name), a = _outArgs(name, what, v);
    if (!m || !a) return;
    if (!displayUndo) displayUndo = { name, mode: m.mode, scale: m.scale, transform: m.transform, vrr: vrrMode(m), pos: m.x + "x" + m.y };
    pendingKeys = Object.assign(pendingKeys || {}, { [what]: v });
    Quickshell.execDetached(["niri", "msg", "output", name].concat(a));
    displayPending = name; displayDeadline = Date.now() + 12000; displayTimer.restart(); monRefresh.restart();
  }
  property var pendingKeys: ({})
  function keepDisplay() {
    if (displayPending && pendingKeys) {
      const k = "dsp_" + displayPending.replace(/-/g, "_") + "_", o = {};
      for (const w in pendingKeys) o[k + w] = pendingKeys[w];
      Prefs.setMany(o); NiriConf.apply();
    }
    displayPending = ""; displayTimer.stop(); displayUndo = null; pendingKeys = ({}); primaryUndo = null;
  }
  function _restoreDisplay() {
    const u = displayUndo; if (!u) return;
    for (const [w, v] of [["mode", u.mode], ["scale", u.scale], ["transform", u.transform], ["vrr", u.vrr], ["position", u.pos]]) {
      const a = _outArgs(u.name, w, v); if (a) Quickshell.execDetached(["niri", "msg", "output", u.name].concat(a));
    }
    displayUndo = null; pendingKeys = ({});
  }
  // primary = at 0x0 and carries the bar: every monitor shifts by the new primary's offset (arrangement kept)
  property var primaryUndo: null
  function setPrimary(name) {
    const ms = System.monitors, p = ms.find(m => m.name === name); if (!p) return;
    const key = n => "dsp_" + n.replace(/-/g, "_") + "_position";
    const old = { primary_monitor: Prefs.get("primary_monitor", "") }, nw = { primary_monitor: name };
    for (const m of ms) { old[key(m.name)] = Prefs.get(key(m.name), ""); nw[key(m.name)] = (m.x - p.x) + "x" + (m.y - p.y) }
    primaryUndo = old; Prefs.setMany(nw); NiriConf.apply();
    displayPending = name; displayDeadline = Date.now() + 12000; displayTimer.restart(); monRefresh.restart();
  }
  function undoPrimary() { if (!primaryUndo) return; Prefs.setMany(primaryUndo); primaryUndo = null; NiriConf.apply() }
  function revertDisplay() { _restoreDisplay(); displayPending = ""; displayTimer.stop(); monRefresh.restart(); undoPrimary() }
  Timer { id: displayTimer; interval: 12500; onTriggered: { root.displayPending = ""; monRefresh.restart(); root._restoreDisplay(); root.undoPrimary() } }
  Timer { id: monRefresh; interval: 1500; onTriggered: System.refresh() }
  // every palette family has its wallpaper folder ~/Pictures/Wallpapers/<family>/ (gruvbox, rose-pine, ...):
  // switching the palette puts a random wallpaper from it (if the folder has any), the picker shows them first
  function family(id) { return ["gruvbox", "rose-pine", "kanagawa", "everforest", "tokyo-night", "adwaita"].find(f => (id || "").startsWith(f)) || "" }
  readonly property string familyDir: family(currentPalette) ? walls + "/" + family(currentPalette) : ""
  // dark <-> light pairs: picking a palette makes its pair the day / night themes, so the Mode switch and the
  // schedule (settings.lua dm:toggle, daynight.lua) stay inside the chosen family
  readonly property var pairs: [["malachite-light", "malachite-dark"], ["sapphire-light", "sapphire-dark"], ["garnet-light", "garnet-dark"],
                                ["amber-light", "amber-dark"], ["amethyst-light", "amethyst-dark"]]
  // Picker option "dark and light separately": day_theme / night_theme are chosen on their own, pairs are not enforced
  readonly property bool split: Prefs.get("palette_split", false) === true
  function isDark(p) {
    const h = p && p.colors && p.colors.length ? p.colors[0] : "";
    return !/^#[0-9a-f]{6}$/i.test(h) || parseInt(h.slice(1, 3), 16) * 0.299 + parseInt(h.slice(3, 5), 16) * 0.587 + parseInt(h.slice(5, 7), 16) * 0.114 <= 140;
  }
  function setPalette(id) {
    const pr = pairs.find(x => x.includes(id));
    if (pr) Prefs.setMany({ day_theme: pr[0], night_theme: pr[1] });
    else {   // no pair for this family: the palette becomes the day or the night theme by its own brightness, the other side stays
      const c = (palettes.find(x => x.id === id) || {}).colors, h = c ? c[0] : "";
      if (/^#[0-9a-f]{6}$/i.test(h)) {
        const lum = parseInt(h.slice(1, 3), 16) * 0.299 + parseInt(h.slice(3, 5), 16) * 0.587 + parseInt(h.slice(5, 7), 16) * 0.114;
        Prefs.set(lum > 140 ? "day_theme" : "night_theme", id);
      }
    }
    // one chain, theme first: in parallel the wallpaper was tinted with the OLD palette when it finished after the theme
    const f = family(id);
    Quickshell.execDetached(["sh", "-c", 'w=""; [ -n "$1" ] && w=$(find "$1" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) | shuf -n1); '
                             + 'THEME_QUIET=1 python3 "$2" set "$3"; [ -n "$w" ] && THEME_QUIET=1 python3 "$2" wallpaper-set "$w"',
                             "sh", f ? walls + "/" + f : "", home + "/.config/themes/theme.py", id]);
  }
  function themeSet(id) { Quickshell.execDetached(["env", "THEME_QUIET=1", "python3", home + "/.config/themes/theme.py", "set", id]) }
  // wallpaper tint in the palette colours: theme.py re-renders the recoloured copy and re-sets it
  function setRecolor(v) { Prefs.set("recolor", v); retheme.restart() }
  function setDim(v) { Prefs.set("wall_dim", v); retheme.restart() }   // wallpaper drawn darker: theme.py renders a darker copy (the lock screen follows)
  Timer { id: retheme; interval: 200; onTriggered: root.themeSet(root.currentPalette) }   // re-render only, keep the wallpaper
  function setWallpaper(path) { Wallpaper.set(path) }
  // keys Hyprland reads from settings.toml (core/prefs.lua): saved there for the next start and applied live now
  readonly property var blurs: ({ off: [false, 8, 2], light: [true, 4, 1], normal: [true, 8, 2], strong: [true, 12, 3] })
  // the whole blur table from the saved choices (level or custom size / passes, then the fine tuning)
  function blurLua() {
    const lvl = Prefs.get("blur", "normal"), b = lvl === "custom" ? [true, Number(Prefs.get("blur_radius", 8)), Number(Prefs.get("blur_layers", 2))] : (blurs[lvl] || blurs.normal);
    return "blur = { enabled = " + b[0] + ", size = " + b[1] + ", passes = " + b[2] + ", noise = " + Number(Prefs.get("blur_noise", 0.03)) + ", brightness = " + Number(Prefs.get("blur_brightness", 0.9))
         + ", contrast = " + Number(Prefs.get("blur_contrast", 0.85)) + ", vibrancy = " + Number(Prefs.get("blur_vibrancy", 0.15)) + ", xray = " + (Prefs.get("blur_xray", false) === true) + " }";
  }
  function setHypr(obj) {
    Prefs.setMany(obj);
    const g = [], d = [];
    if ("gaps" in obj) g.push("gaps_out = " + obj.gaps);
    if ("border_width" in obj) g.push("border_size = " + obj.border_width);
    if ("round_windows" in obj) d.push("rounding = " + obj.round_windows);
    if (Object.keys(obj).some(k => k === "blur" || k.startsWith("blur_"))) d.push(blurLua())
    const parts = [];
    if (g.length) parts.push("general = { " + g.join(", ") + " }");
    if (d.length) parts.push("decoration = { " + d.join(", ") + " }");
    if (parts.length) { NiriConf.apply(); hyprTouched() }
    // opacity is baked into generated-colors.lua by theme.py (rules.lua reads it from there, not settings.toml
    // directly) — a bare reload alone kept re-reading the stale render, so the custom slider never stuck.
    if ("opacity" in obj) { themeSet(currentPalette); reload.restart() }
  }
  Timer { id: reload; interval: 400; onTriggered: { NiriConf.apply(); root.hyprTouched() } }
}
