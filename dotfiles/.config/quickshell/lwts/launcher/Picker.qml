// Horizontal picker with previews (Settings -> Look -> Wallpaper / Palette). The launcher drop widens into a strip,
// windows are moved out of sight (empty workspace) so the desktop itself is the preview.
// Wallpaper: a strip of thumbnails, applied live while you move or hover (debounced); Enter / click keeps it, Esc / click outside restores.
// Palette: a reel (case-opening style): the cards slide under a fixed marker, the card under the marker is the choice and is shown live.
// A card is a family: dark and light side by side. Option "Dark and light apart": two reels, one theme per card, chosen on their own.
// Keys (forwarded by Launcher.qml): ← → choose, ↑ ↓ option switch / reels, Enter apply, Esc back. No hint text on screen.
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: pk
  property string kind: ""          // wallpaper | palette
  property string original: ""
  property bool origDark: true      // palette: the mode on screen when the picker opened
  property real px: -1000; property real py: -1000   // last real pointer position (window coords)
  property bool dirty: false        // a live preview was sent: Esc must send the original back
  signal done()
  spacing: 8

  // ---- palette data ----
  readonly property bool split: kind === "palette" && Look.split
  property bool optsInBar: false      // set by the Launcher: the options are drawn in the screen bar
  property bool onSwitch: false     // the keyboard cursor is on the options bar above the reels
  property int optIdx: 0            // which option / chip of the bar
  readonly property var tints: [["off", "Off"], ["soft", "Soft"], ["full", "Full"]]   // wallpaper tint = Look.setRecolor
  readonly property var dims: [["off", "Off"], ["light", "Low"], ["strong", "High"]]   // wallpaper dimming = Look.setDim; chips 0-2 tint, 3-5 dim
  function activateOpt() { if (kind === "palette") Prefs.set("palette_split", !Look.split); else if (optIdx < 3) Look.setRecolor(tints[optIdx][0]); else Look.setDim(dims[optIdx - 3][0]) }
  function enterOpts() { live.stop(); optIdx = kind === "wallpaper" ? Math.max(0, tints.findIndex(t => t[0] === Prefs.get("recolor", "off"))) : 0; onSwitch = true }
  property int row: 0               // reel with the cursor: 0 = families / dark, 1 = light (split only)
  property int idx0: 0
  property int idx1: 0
  readonly property var darkItems: Look.palettes.filter(p => Look.isDark(p)).map(p => ({ label: p.label, pals: [p] }))
  readonly property var lightItems: Look.palettes.filter(p => !Look.isDark(p)).map(p => ({ label: p.label, pals: [p] }))
  function famName(pals) {   // the shared leading words: "Gruvbox Dark" + "Gruvbox Light" = "Gruvbox"
    if (pals.length < 2) return pals[0].label;
    const a = pals[0].label.split(" "), b = pals[1].label.split(" "); let n = 0;
    while (n < a.length && n < b.length && a[n] === b[n]) n++;
    return n > 0 ? a.slice(0, n).join(" ") : pals[0].label
  }
  readonly property var famItems: {   // one card per family: [dark, light]
    const out = [], used = ({});
    for (const p of Look.palettes) {
      if (used[p.id]) continue;
      const pr = Look.pairs.find(x => x.includes(p.id)), mid = pr ? (pr[0] === p.id ? pr[1] : pr[0]) : "";
      const mate = mid ? Look.palettes.find(q => q.id === mid) : null;
      used[p.id] = true; if (mate) used[mate.id] = true;
      const pals = mate ? (Look.isDark(p) ? [p, mate] : [mate, p]) : [p];
      out.push({ label: famName(pals), pals: pals });
    }
    return out
  }
  function reelItems(r) { return kind === "wallpaper" ? wallList : split ? (r === 0 ? darkItems : lightItems) : famItems }
  function palId(it) { return split ? it.pals[0].id : (it.pals.find(p => Look.isDark(p) === origDark) || it.pals[0]).id }   // a family keeps the mode on screen
  function idxOf(r, id) { return Math.max(0, reelItems(r).findIndex(it => it.pals.some(p => p.id === id))) }
  function activeIdx() { return row === 0 ? idx0 : idx1 }
  function setActive(v) { if (row === 0) idx0 = v; else idx1 = v }
  function reelOf(r) { return r === 1 ? reelB : reelA }
  function curPalId() { const l = reelItems(row); return l.length ? palId(l[Math.min(activeIdx(), l.length - 1)]) : "" }
  function rebuild() {   // start / option switched: cursor on the saved themes, reels spin in
    row = split ? (origDark ? 0 : 1) : 0;
    if (split) { idx0 = idxOf(0, Prefs.get("night_theme", original)); idx1 = idxOf(1, Prefs.get("day_theme", original)) }
    else idx0 = idxOf(0, original);
    Qt.callLater(() => { reelA.spin(idx0); reelB.spin(idx1) });
  }
  Connections { target: Look; function onSplitChanged() { if (pk.kind === "palette") pk.rebuild() } }

  // wallpapers: the current palette's folder first, then the common ones
  readonly property var wallList: { const a = [], b = []; for (let i = 0; i < own.count; i++) a.push(own.get(i, "filePath"));
                                    for (let i = 0; i < walls.count; i++) b.push(walls.get(i, "filePath")); return a.concat(b) }
  readonly property int count: kind === "wallpaper" ? wallList.length : reelItems(row).length
  function start(k) {
    kind = k; dirty = false; touched = false; onSwitch = false; origDark = Session.dark;
    row = 0;
    if (k === "wallpaper") { original = Wallpaper.original || Look.currentWall; idx0 = Math.max(0, wallIndex(original)); Qt.callLater(() => reelA.spin(idx0)) }
    else { original = Look.currentPalette; rebuild() }
    reelA.forceActiveFocus(); refocus.restart();
  }
  // the folder models fill asynchronously: until the user moves, keep the highlight on the wallpaper that is set
  property bool touched: false
  function sync() {
    if (touched || kind !== "wallpaper") return;
    idx0 = Math.max(0, wallIndex(original));
    reelA.spin(idx0);
  }
  onWallListChanged: Qt.callLater(sync)
  Timer { id: refocus; interval: 400; onTriggered: reelA.forceActiveFocus() }   // after the workspace switch
  function wallIndex(path) { return wallList.indexOf(path) }
  function move(d) {
    const n = count; if (n < 1) return;
    setActive(((activeIdx() + d) % n + n) % n);   // endless: past the last card comes the first
    reelOf(row).shift(d, 240); touched = true; live.restart(); stepped()
  }
  // Easter egg: scrolling non-stop for a long time (777 steps in a run, each within 0.45 s of the last: about half a minute of non-stop scrolling): when it stops, the jackpot
  property int run: 0
  property real runStart: 0
  function stepped() { if (run === 0) runStart = Date.now(); run++; runEnd.restart() }
  Timer { id: runEnd; interval: 450; onTriggered: { if (pk.run >= 777) Sounds.egg("reel-jackpot"); pk.run = 0 } }
  function switchRow() {   // split: Up / Down between the dark and the light reel
    row = 1 - row; touched = true; live.restart();
  }
  function cardClicked(r, i) {   // a card under the marker is applied, any other one slides to the marker first
    onSwitch = false; row = r;
    if (i === activeIdx()) { apply(); return }
    setActive(i); reelOf(r).jump(i, 260); touched = true; live.restart();
  }
  function apply() {   // click / Enter
    live.stop();
    if (kind === "palette") {
      const id = curPalId();
      if (split) {   // only that side changes; the other side keeps its theme
        Prefs.set(row === 0 ? "night_theme" : "day_theme", id);
        Look.themeSet((row === 0) === origDark ? id : original)   // the other mode's theme was only previewed: back to what is on screen
      } else Look.setPalette(id);
    } else Look.setWallpaper(wallList[idx0]);
    done();
  }
  function cancel() {   // Esc / click outside: back to what was there
    live.stop();
    if (kind === "wallpaper" && original && dirty) Look.setWallpaper(original);
    if (kind === "palette" && original && dirty) Look.themeSet(original);
    done();
  }
  function handleKey(e) {
    const k = e.key;
    if (k === Qt.Key_Backspace) { cancel(); return true }   // back, like Esc
    if (onSwitch) {   // the options bar: Enter / Space sets, Left / Right between chips, Down goes back to the reel
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activateOpt();
      else if (k === Qt.Key_Left) optIdx = Math.max(0, optIdx - 1);
      else if (k === Qt.Key_Right) optIdx = Math.min(kind === "wallpaper" ? 5 : 0, optIdx + 1);
      else if (k === Qt.Key_Down) { onSwitch = false; touched = true; live.restart() }
      else if (k === Qt.Key_Escape) cancel();
      else if (k !== Qt.Key_Up) return false;
    }
    else if (k === Qt.Key_Up) { if (split && row === 1) switchRow(); else enterOpts() }
    else if (k === Qt.Key_Down) { if (split && row === 0) switchRow() }
    else if (k === Qt.Key_Right || k === Qt.Key_Down) move(1);
    else if (k === Qt.Key_Left || k === Qt.Key_Up) move(-1);
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) apply();
    else if (k === Qt.Key_Escape) cancel();
    else return false;
    return true;
  }

  TapHandler { acceptedButtons: Qt.RightButton | Qt.BackButton; onTapped: pk.cancel() }   // mouse: right click / the Back button = back to Settings
  Timer { id: live; interval: pk.kind === "palette" ? 500 : 250
          onTriggered: { pk.dirty = true; pk.kind === "palette" ? Look.themeSet(pk.curPalId()) : Look.setWallpaper(pk.wallList[pk.idx0]) } }

  FolderListModel {
    id: own
    folder: Look.familyDir ? "file://" + Look.familyDir : ""
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    showDirs: false
  }
  FolderListModel {
    id: walls
    folder: "file://" + Look.walls
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    showDirs: false
  }

  // ---- palette cards ----
  PickerOpts {   // in the bar (bar/Bar.qml) when there is one, here otherwise
    Layout.alignment: Qt.AlignHCenter
    picker: pk
    visible: pk.kind !== "" && !pk.optsInBar
  }
  PaletteReel {
    id: reelA
    picker: pk
    visible: pk.kind !== ""
    Layout.fillWidth: true; Layout.preferredHeight: 124
    rowIdx: 0; items: pk.kind === "wallpaper" ? pk.wallList : pk.split ? pk.darkItems : pk.famItems; selected: pk.idx0
  }
  PaletteReel {
    id: reelB
    picker: pk
    visible: pk.split
    Layout.fillWidth: true; Layout.preferredHeight: 124
    rowIdx: 1; items: pk.lightItems; selected: pk.idx1
  }
}
