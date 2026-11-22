// Quick settings (Super+Space, empty search): tiles, volume, mini player.
// Tiles: `qs_tiles` in settings.toml (order = order on screen); a tile whose hardware is missing is not shown.
// Keyboard (forwarded by Launcher.qml, focus stays in the search field): arrows move, Enter acts, Shift+Enter = details,
// Shift+← → = volume from anywhere.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: qs
  signal closeRequested()
  signal details(string panel)
  spacing: 6   // launcher v2: compact

  // ---- tiles (registry + packing: Tiles singleton, settings_spec 2.1-2.2) ---------------
  readonly property var all: Tiles.all
  readonly property var tiles: Tiles.active   // [{ id, wide }], in order
  readonly property var rows: Tiles.layoutRows   // [[{ id, wide, slots }]] - the user's own rows (Settings -> Features -> Quick settings)

  // ---- player -------------------------------------------------------------------------
  readonly property var players: Mpris.players.values.filter(p => !(p.dbusName || "").includes("playerctld"))
  readonly property var player: MediaPick.player

  // ---- bars (`qs_bars` in settings.toml; brightness only where there is a backlight). Enter = mute, Shift+Enter = mixer ----
  readonly property real volMax: Prefs.get("audio_overdrive", false) ? 1.5 : 1   // overdrive: the bar spans 0..150%
  readonly property var barDefs: ({
    light: { icon: () => "sun", off: () => false, value: () => Brightness.value, set: v => Brightness.set(v),
             step: d => Brightness.step(d), text: () => Math.round(Brightness.value * 100) + "%" },
    vol:   { icon: () => Audio.icon, off: () => Audio.muted, value: () => Math.min(1, Audio.volume / qs.volMax),
             set: v => Audio.setVolume(v * qs.volMax), step: d => Audio.step(d), text: () => Math.round(Audio.volume * 100) + "%",
             toggle: () => Audio.toggleMute(), panel: "audio",
             name: () => Audio.outs.length > 1 ? Audio.shortName(Audio.sink) : "Sound", next: d => Audio.nextOut(d), many: () => Audio.outs.length > 1 },
    mic:   { icon: () => Audio.micMuted ? "microphone-slash" : "microphone", off: () => Audio.micMuted, value: () => Audio.micVolume,
             set: v => Audio.setMicVolume(v), step: d => Audio.micStep(d), text: () => Math.round(Audio.micVolume * 100) + "%",
             toggle: () => Audio.toggleMic(), panel: "audio",
             name: () => Audio.ins.length > 1 ? Audio.shortName(Audio.source) : "Mic", next: d => Audio.nextIn(d), many: () => Audio.ins.length > 1 },
  })
  readonly property var bars: ["light", "vol", "mic"].filter(id => Prefs.get("qs_bars", ["light", "vol"]).includes(id)
                                                                  && (id !== "light" || Brightness.available) && (id !== "mic" || !!Audio.source))

  // ---- tray tile (concept: concepts/qs-tiles.md): the tile IS its icons. Enter on it drops the highlight onto the icons,
  // <- -> move between them, Enter opens that app's menu (shown right under the grid), Esc / Up go up one level ----
  property bool inIcons: false
  property int iconIdx: 0
  property int iconOffset: 0       // first app icon shown on the tile (overflow slides the window; the panel never grows)
  property bool picked: false      // an app is chosen: the tile now shows two buttons, Open and Quit
  property int actIdx: 0           // 0 = open / go to its window, 1 = quit it completely
  property int trayShown: 0        // app icons the tile has room for (reported by the tile)
  readonly property bool inside: inIcons || picked
  readonly property var trayItems: SystemTray.items.values
  function reveal() {              // keep the picked icon inside the visible window
    const n = Math.max(1, trayShown);
    if (iconIdx < iconOffset) iconOffset = iconIdx; else if (iconIdx >= iconOffset + n) iconOffset = iconIdx - n + 1;
  }
  function pick(i) { iconIdx = i; inIcons = true; picked = true; actIdx = 0; reveal() }
  function pageIcons() {           // the "+N" chip: next page, wrapping round
    const n = Math.max(1, trayShown), next = iconOffset + n;
    iconOffset = next < trayItems.length ? next : 0;
  }
  function windowOf(it) {          // the app's niri window, matched by words of the tray id / title against app_id / title
    const stop = ["status", "icon", "tray", "indicator", "applet", "desktop", "client"];
    const words = ((it.id || "") + " " + (it.title || "") + " " + (it.tooltipTitle || "")).toLowerCase().split(/[^a-zа-яіїєґ0-9]+/).filter(w => w.length >= 4 && !stop.includes(w));
    const hit = (text, x) => { const t = text.toLowerCase(); return t.includes(x) || t.replace(/[^a-zа-яіїєґ0-9]/g, "").includes(x) };   // "TelegramDesktop" vs "org.telegram.desktop"
    const list = Compositor.windowList;
    return list.find(w => words.some(x => hit(w.app_id || "", x))) || list.find(w => words.some(x => hit(w.title || "", x))) || null;   // app_id first, a title only as the fallback
  }
  function openApp(it) { const w = windowOf(it); if (w) Compositor.focusWindow(w.id); else it.activate() }
  // quit = the app's own "Quit" entry (graceful); no such entry -> TERM to its window's process
  property var quitItem: null
  QsMenuOpener { id: quitOpener; menu: qs.quitItem && qs.quitItem.hasMenu ? qs.quitItem.menu : null }
  Timer {
    id: quitTimer; interval: 200
    onTriggered: {
      const it = qs.quitItem; if (!it) return;
      const ents = quitOpener.children ? quitOpener.children.values : [];
      const e = ents.filter(x => x && !x.isSeparator && x.enabled && /quit|exit|вих|выхо|выйти|закр|close/i.test(x.text || "")).pop();
      if (e) e.triggered(); else { const w = qs.windowOf(it); if (w && w.pid) Quickshell.execDetached(["kill", "-TERM", String(w.pid)]) }
      qs.quitItem = null;
    }
  }
  function quitApp(it) { quitItem = it; quitTimer.restart() }
  function runAction() {
    const it = trayItems[iconIdx]; if (!it) return;
    if (actIdx === 0) openApp(it); else quitApp(it);
    picked = false; inIcons = false; closeRequested();
  }

  // ---- launcher v2 layout: quiet text chips (switches) + key/value rows (info, drill-in) -----------------
  // Order = the user's rows flattened. chip = a plain switch; row = toggleless / tray / timed tiles. Both keep the "t:<id>" focus ids.
  readonly property var flatIds: Tiles.flatten(rows).map(t => t.id)
  function isRow(id) { const d = all[id]; return !!d && (!!d.toggleless || !!d.drill || !!d.progress) }
  readonly property var widgetIds: flatIds.filter(id => all[id] && Tiles.wideIds.includes(id))   // Settings -> Quick settings: shown as a live tile, below the text
  readonly property var chipIds: flatIds.filter(id => all[id] && !isRow(id) && !widgetIds.includes(id))
  readonly property bool hasVolBar: bars.includes("vol")
  readonly property var rowIds: flatIds.filter(id => isRow(id) && !widgetIds.includes(id) && !(id === "mixer" && hasVolBar))   // the sound bar already links to the mixer
  readonly property int perRow: Math.max(1, Math.min(6, chipIds.length))
  readonly property var chipRows: { const o = []; for (let k = 0; k < chipIds.length; k += 6) o.push(chipIds.slice(k, k + 6)); return o }
  function valueOf(id) {
    const d = all[id]; if (!d) return "";
    if (d.status) { const v = d.status(); if (v !== "") return v }
    if (id === "clock") return Qt.formatDateTime(qsClock.date, "ddd d MMM")
    if (id === "notif") return Notifs.dnd ? "Do not disturb" : Notifs.unread > 0 ? Notifs.unread + " new" : "Quiet"
    return "";
  }
  readonly property var shortNames: ({ notif: "Notif", profile: "Profile", sysmon: "System", flight: "Flight", dnd: "DND", wifi: "Wi-Fi", clip: "Clip" })
  function nameOf(id) { return shortNames[id] || (all[id] ? all[id].label() : id) }
  SystemClock { id: qsClock; precision: SystemClock.Minutes }
  readonly property var grid: {
    const g = chipRows.map(r => r.map(id => "t:" + id));
    for (const b of bars) g.push(["b:" + b]);
    for (const id of rowIds) if (id !== "tray") g.push(["t:" + id]);
    for (const r of Tiles.packRows(widgetIds, width, Math.round(38 * Theme.scale))) g.push(r.map(id => "t:" + id));
    if (player) g.push(["m:prev", "m:play", "m:next"]);
    if (rowIds.includes("tray")) g.push(["t:tray"]);
    return g;
  }
  property int row: -1   // -1 = nothing focused until an arrow is pressed
  property int col: 0
  readonly property string focusId: row < 0 ? "" : ((grid[row] || [])[Math.min(col, (grid[row] || [""]).length - 1)] || "")
  // ---- Alt hints (launcher v2): bare letters belong to the search, so tile letters live on Alt. Hold Alt = letters show on the
  // tiles; Alt+letter acts, Alt+Shift+letter = details. Letters follow the keyboard layout (q w e r / a s d f / z x c v), same place as on screen.
  property bool hints: false
  readonly property var hintMap: {
    // keyboard-shaped, LEFT HAND ONLY (Alt + one hand): each chip row takes a keyboard row (q w e r t / a s d f g / z x c v), then
    // the key/value rows below take the next keyboard row left to right. A 6th chip in a row gets no letter.
    const kb = ["qwert", "asdfg", "zxcv"], m = {};
    let kr = 0;
    for (const r of chipRows) { const L = kb[Math.min(kr, 2)]; r.forEach((id, i) => { if (i < L.length) m[id] = L[i].toUpperCase() }); kr++ }
    const L = kb[Math.min(kr, 2)]; let i = 0;
    for (const id of rowIds) { if (i < L.length) m[id] = L[i++].toUpperCase() }
    if (i > 0) kr++;
    const W = kb[Math.min(kr, 2)]; let j = 0;   // widgets: the next keyboard row (letters already taken are skipped)
    const used = Object.values(m);
    for (const id of widgetIds) { while (j < W.length && used.includes(W[j].toUpperCase())) j++; if (j < W.length) m[id] = W[j++].toUpperCase() }
    return m;
  }
  function hintFor(id) { return hints ? (hintMap[id] || "") : "" }
  function altKey(e) {   // true = an Alt+letter was used
    if (!(e.modifiers & Qt.AltModifier) || e.key < Qt.Key_A || e.key > Qt.Key_Z) return false;
    const ch = String.fromCharCode(e.key);
    for (const id in hintMap) if (hintMap[id] === ch) { if (!e.isAutoRepeat) act("t:" + id, e.modifiers & Qt.ShiftModifier); return true }
    return false;
  }
  function reset() { hints = false; row = -1; col = 0; inIcons = false; picked = false; iconOffset = 0; Session.refresh(); Brightness.refresh() }

  function act(id, shift) {
    const [k, v] = id.split(":");
    if (k === "t") { const t = all[v]; if (t.drill) { if (trayItems.length) { inIcons = true; iconIdx = 0 } } else if (shift) { if (t.details) t.details(); else if (t.panel) details(t.panel) } else if (t.toggleless && t.panel) details(t.panel); else t.act() }   // toggleless with an act (data widgets, tools) act on Enter
    else if (k === "b") { const b = barDefs[v]; if (shift && b.panel) details(b.panel); else if (b.toggle) b.toggle() }
    else if (k === "m" && player) { if (v === "prev") player.previous(); else if (v === "next") player.next(); else player.togglePlaying() }
  }
  function handleKey(e) {   // true = used
    if (e.key === Qt.Key_Alt) { hints = true; return false }
    if (altKey(e)) return true;
    const shift = e.modifiers & Qt.ShiftModifier;
    if (shift && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) { Audio.step(e.key === Qt.Key_Right ? 0.05 : -0.05); return true }
    // Tray tile navigation: no level needs Esc to get out. Any arrow that has nowhere to go inside leaves the tile and moves
    // the grid focus on (falls through to the grid code below); Esc leaves the whole tile at once.
    if (picked) {   // [Open] [Quit] on the tile
      if (e.key === Qt.Key_Left) { if (actIdx === 0) picked = false; else actIdx = 0; return true }   // Left of Open = back to the icons
      else if (e.key === Qt.Key_Right) { actIdx = 1; return true }
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (!e.isAutoRepeat) runAction(); return true }
      else if (e.key === Qt.Key_Escape) { picked = false; inIcons = false; return true }
      else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) { picked = false; inIcons = false }
      else return false;
    } else if (inIcons) {
      const n = trayItems.length;
      if (e.key === Qt.Key_Left && iconIdx > 0) { iconIdx--; reveal(); return true }
      else if (e.key === Qt.Key_Right && iconIdx < n - 1) { iconIdx++; reveal(); return true }
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (!e.isAutoRepeat) pick(iconIdx); return true }
      else if (e.key === Qt.Key_Escape) { inIcons = false; return true }
      else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(e.key)) inIcons = false;   // an edge / up / down: on to the neighbour tile
      else return false;
    }
    if (row < 0 && [Qt.Key_Down, Qt.Key_Up, Qt.Key_Left, Qt.Key_Right].includes(e.key)) { row = 0; col = 0; return true }
    if (e.key === Qt.Key_Down) row = Math.min(row + 1, grid.length - 1);
    else if (e.key === Qt.Key_Up) row = Math.max(row - 1, 0);
    else if (focusId.startsWith("b:") && e.key === Qt.Key_Space && barDefs[focusId.slice(2)].next) barDefs[focusId.slice(2)].next(shift ? -1 : 1);   // Space = next output / input
    else if (focusId.startsWith("b:") && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) barDefs[focusId.slice(2)].step(e.key === Qt.Key_Right ? 0.05 : -0.05);
    else if (e.key === Qt.Key_Right) col = Math.min(col + 1, grid[row].length - 1);
    else if (e.key === Qt.Key_Left) col = Math.max(col - 1, 0);
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
      if (e.isAutoRepeat) return true;
      if (focusId) act(focusId, shift);
    }
    else return false;
    return true;
  }
  function handleRelease(e) { if (e.key === Qt.Key_Alt) hints = false }

  // ---- look: chips, a dotted rule, bars, a dotted rule, key/value rows ----------------------------------------
  Flow {
    id: chipFlow
    Layout.fillWidth: true
    visible: qs.chipIds.length > 0
    Repeater {
      model: qs.chipIds
      UiChip {
        required property string modelData
        readonly property var t: qs.all[modelData]
        width: chipFlow.width / qs.perRow
        text: qs.nameOf(modelData); on: t.on()
        focusedChip: qs.focusId === "t:" + modelData
        hint: qs.hintFor(modelData)
        onAct: qs.act("t:" + modelData, false)
        onDetails: qs.act("t:" + modelData, true)
      }
    }
  }
  UiDotLine { Layout.fillWidth: true; visible: qs.chipIds.length > 0 && (qs.bars.length > 0 || qs.rowIds.length > 0) }

  Repeater {   // bars: brightness / sound / mic, each optional (Settings -> Features -> Bars)
    model: qs.bars
    UiKvRow {
      required property string modelData
      readonly property var b: qs.barDefs[modelData]
      Layout.fillWidth: true
      key: b.name ? b.name() : "Bright"
      keyClickable: !!b.many && b.many()
      onKeyClicked: b.next(1)
      track: b.value(); trail: b.text().replace("%", ""); off: b.off()
      focusedRow: qs.focusId === "b:" + modelData
      onMoved: v => b.set(v)
      onDetails: if (b.panel) qs.details(b.panel)
      onAct: if (b.toggle) b.toggle()
    }
  }
  UiDotLine { Layout.fillWidth: true; visible: qs.bars.length > 0 && qs.rowIds.length > 0 }

  Component {   // one key/value row (info / drill-in): shared by the rows below and the tray, which sits on the POWER line
    id: kvDelegate
    UiKvRow {
      id: kv
      required property string modelData
      readonly property var t: qs.all[modelData]
      readonly property bool isTray: !!t.drill
      Layout.fillWidth: true
      key: isTray ? "" : qs.nameOf(modelData)   // the tray is just its icons
      value: qs.valueOf(modelData)
      timed: !!t.progress && t.progress() >= 0
      led: t.on ? t.on() : false
      custom: isTray
      focusedRow: qs.focusId === "t:" + modelData
      hint: qs.hintFor(modelData)
      onAct: qs.act("t:" + modelData, false)
      onDetails: qs.act("t:" + modelData, true)
      Row {   // tray: the apps' icons (click = pick), or [Open] [Quit] once one is picked
        visible: kv.isTray
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        readonly property var icons: kv.isTray ? t.icons() : []
        readonly property int cap: Math.max(1, Math.floor(kv.width * 0.55 / 24))
        readonly property bool overflow: icons.length > cap
        readonly property int shown: overflow ? Math.max(1, cap - 1) : icons.length
        onShownChanged: if (kv.isTray) qs.trayShown = shown
        Component.onCompleted: if (kv.isTray) qs.trayShown = shown
        Repeater {
          model: qs.picked ? [] : parent.icons.slice(qs.iconOffset, qs.iconOffset + parent.shown)
          MouseArea {
            required property var modelData
            required property int index
            implicitWidth: 20; implicitHeight: 20
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: qs.pick(qs.iconOffset + index)
            scale: qs.inIcons && qs.iconIdx === qs.iconOffset + index ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
            Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"; border.width: 2; border.color: Theme.ring
                        opacity: qs.inIcons && qs.iconIdx === qs.iconOffset + parent.index ? 1 : 0 }
            AppIcon { anchors.centerIn: parent; source: parent.modelData; size: 15 }
          }
        }
        MouseArea {   // overflow chip: next page
          visible: !qs.picked && parent.overflow
          implicitWidth: ovf.implicitWidth + 10; implicitHeight: 20
          cursorShape: Qt.PointingHandCursor
          onClicked: qs.pageIcons()
          Text { id: ovf; anchors.centerIn: parent; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale)
                 text: qs.iconOffset + parent.parent.shown < parent.parent.icons.length ? "+" + (parent.parent.icons.length - qs.iconOffset - parent.parent.shown) : "‹" }
        }
        Repeater {
          model: qs.picked ? ["Open", "Quit"] : []
          UiButton {
            required property string modelData
            required property int index
            text: modelData; flat: true; focusedChip: qs.actIdx === index
            onClicked: { qs.actIdx = index; qs.runAction() }
          }
        }
      }
    }
  }
  Repeater { model: qs.rowIds.filter(id => id !== "tray"); delegate: kvDelegate }

  ColumnLayout {   // tiles: rows of 4 units (icon 1 / default 2 / wide 4, Tiles.packRows); a row that is not full stretches its tiles
    Layout.fillWidth: true
    visible: qs.widgetIds.length > 0
    spacing: 6
    Repeater {
      model: Tiles.tileRows(qs.widgetIds, qs.width, Math.round(38 * Theme.scale), 6)
      RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: modelData.spacing
        Repeater {
          model: parent.modelData.items
          Tile {
            required property var modelData
            readonly property string tid: modelData.id
            readonly property var t: qs.all[tid]
            Layout.preferredWidth: modelData.w
            wide: Tiles.sizeOf(tid) !== "icon"
            readonly property var f: Tiles.face(tid)
            icon: f.icon; label: qs.nameOf(tid); status: f.status; hero: f.hero; alert: f.alert; info: f.info; on: t.on()
            progress: t.progress ? t.progress() : -1
            focused: qs.focusId === "t:" + tid
            hint: qs.hintFor(tid)
            onAct: qs.act("t:" + tid, false)
            onDetails: qs.act("t:" + tid, true)
          }
        }
      }
    }
  }


  Item {   // compact player (only while a player exists): line 1 = title + artist, controls on the right; line 2 = dot progress + time
    id: mp
    visible: !!qs.player
    Layout.fillWidth: true
    implicitHeight: Math.round(46 * Theme.scale)
    readonly property real pos: qs.player && qs.player.length > 0 ? Math.max(0, Math.min(1, qs.player.position / qs.player.length)) : 0
    function mmss(sec) { sec = Math.max(0, Math.floor(sec)); return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0") }
    Timer { running: mp.visible && !!qs.player && qs.player.isPlaying; interval: 1000; repeat: true; onTriggered: qs.player.positionChanged() }
    ColumnLayout {
      anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 2; bottomMargin: 2 }
      spacing: 4
      RowLayout {
        Layout.fillWidth: true; spacing: 8
        Item {   // title: clipped; when it does not fit it scrolls to the end and back (pauses at both ends)
          id: tbox
          Layout.fillWidth: true; Layout.preferredHeight: ttl.implicitHeight; clip: true
          readonly property real over: Math.max(0, ttl.implicitWidth - width)
          Text {
            id: ttl
            text: qs.player ? (qs.player.trackTitle || qs.player.identity || "") + (qs.player.trackArtist ? "  ·  " + qs.player.trackArtist : "") : ""
            color: Theme.text; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
            onTextChanged: x = 0
          }
          SequentialAnimation {
            running: tbox.over > 0 && mp.visible; loops: Animation.Infinite
            onRunningChanged: if (!running) ttl.x = 0
            PauseAnimation { duration: 1500 }
            NumberAnimation { target: ttl; property: "x"; to: -tbox.over; duration: Math.max(800, tbox.over * 30); easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1200 }
            NumberAnimation { target: ttl; property: "x"; to: 0; duration: Math.max(800, tbox.over * 30); easing.type: Easing.InOutSine }
          }
        }
        Repeater {
          model: [["m:prev", "skip-back"], ["m:play", qs.player && qs.player.isPlaying ? "pause" : "play"], ["m:next", "skip-forward"]]
          MouseArea {
            required property var modelData
            implicitWidth: 24; implicitHeight: 22
            cursorShape: Qt.PointingHandCursor; hoverEnabled: true
            onClicked: qs.act(modelData[0], false)
            Rectangle { anchors.fill: parent; radius: Theme.radiusCtl
                        color: parent.containsMouse ? Theme.fillHover : "transparent"
                        border.width: qs.focusId === parent.modelData[0] ? 2 : 0; border.color: Theme.ring }
            Icon { anchors.centerIn: parent; name: parent.modelData[1]; fill: true; font.pixelSize: 15; color: Theme.text }
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true; spacing: 8
        DotMeter { Layout.fillWidth: true; Layout.preferredHeight: 4; fit: width; dotSize: 3; gap: 3; value: mp.pos }
        UiCaption { text: qs.player && qs.player.length > 0 ? mp.mmss(qs.player.position) + " / " + mp.mmss(qs.player.length) : "" }
      }
    }
  }

  UiDotLine { Layout.fillWidth: true }
  RowLayout {   // the tray row (its icons)
   visible: qs.rowIds.includes("tray")
   Layout.fillWidth: true; spacing: 0
  Repeater { model: qs.rowIds.includes("tray") ? ["tray"] : []; delegate: kvDelegate }

  }
}
