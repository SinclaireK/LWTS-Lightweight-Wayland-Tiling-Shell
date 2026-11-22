// Session (bar: the dot-matrix button in the right corner). Two halves:
//   LEFT  : the timer, always open: minutes in the dot font, a dot track you drag (5..120 min, wheel +-5), [SLEEP] / [POWER OFF], [START].
//   RIGHT : a filled square with the four power actions as chunky dot-matrix icons, a 2x2 grid (Lock, Sleep / Reboot, Power off). Lock is instant,
//           the other three need a held press (700 ms): a red sweep over the icon's dots and the tile, rolls back when let go early. The picked tile
//           shows its own name under its icon (the icon lifts a little; nothing is captioned at rest). No outlines, no focus frames: selection = a quiet fill.
//   RUNNING: the timer takes the WHOLE drop (the drop shrinks a little): countdown, draining track, [PAUSE] / [RESUME], [CANCEL]. The power icons are
//           hidden while it runs (cancel the timer to get them back).
// Keys: arrows move spatially in the 2x2 (first press = Lock; Left of the first column = the timer, Right of the timer = Lock); on the timer Up / Down = +-5 min, Tab = action,
// Enter = start / pause / resume. Enter / Space on an icon = hold. Esc closes. Module `powertimer`; none = only the rectangle.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: p
  spacing: 0
  focus: true
  readonly property bool wantsKeys: true
  readonly property real dropWidth: !pt ? 120 : tRun ? 280 : 300   // the drop eases between these (Popups animates fullWidth)
  signal closeMe()

  readonly property var pt: Tiles.all.powertimer
  readonly property var tmr: pt ? pt.api : null   // the module's own PowerTimer instance (see modules/powertimer/Tiles.qml)
  readonly property var items: [
    { id: "lock", label: "Lock", hold: false },
    { id: "sleep", label: "Sleep", hold: true },
    { id: "reboot", label: "Reboot", hold: true },
    { id: "poweroff", label: "Power off", hold: true },
  ]
  readonly property var nav: [   // per tile (2x2: Lock Sleep / Reboot Power off): left / right / up / down neighbour; left of the first column = the timer
    { l: timerIdx, r: 1, u: 0, d: 2 }, { l: 0, r: 1, u: 1, d: 3 },
    { l: timerIdx, r: 3, u: 0, d: 2 }, { l: 2, r: 3, u: 1, d: 3 }]
  readonly property int timerIdx: pt ? items.length : -1
  property int idx: -1          // the picked stop; -1 = nothing picked yet
  property string holding: ""
  property real holdP: 0
  readonly property bool tRun: !!pt && (tmr.on || tmr.paused)
  readonly property string tAct: tmr.on ? tmr.action : tmr.nextAction
  property bool editing: false  // the minutes are being typed (click the number, or just press a digit)
  function startEdit(first) {
    editing = true; heroEdit.text = first !== "" ? first : String(tmr.nextMinutes)
    heroEdit.forceActiveFocus(); if (first !== "") heroEdit.cursorPosition = heroEdit.text.length; else heroEdit.selectAll()
  }
  function endEdit(commit) {
    if (!editing) return
    editing = false
    const v = parseInt(heroEdit.text)
    if (commit && v > 0) tmr.remember("", Math.min(999, v))
    p.forceActiveFocus()
  }
  property int dragMin: -1      // minutes while the track is dragged (committed on release)
  function dragTo(v) { dragMin = Math.max(5, Math.round(Math.max(0, Math.min(1, v)) * 24) * 5) }
  function commitDrag() { if (dragMin < 0) return; tmr.remember("", dragMin); dragMin = -1 }
  function timerEnter() { if (tmr.on) tmr.pause(); else if (tmr.paused) tmr.resume(); else tmr.start() }
  NumberAnimation on holdP { id: holdAnim; running: false; from: 0; to: 1; duration: 700
                             onFinished: if (p.holding) { const w = p.holding; p.holding = ""; p.closeMe(); Session.power(w) } }
  function press(it) {
    if (!it.hold) { closeMe(); Session.power(it.id); return }
    holding = it.id; holdAnim.restart()
  }
  function release() { if (holding) { holdAnim.stop(); holding = ""; holdP = 0 } }

  Keys.onPressed: e => {
    const onTimer = idx === timerIdx && timerIdx >= 0;
    if (e.key === Qt.Key_Escape) { closeMe(); e.accepted = true; return }
    if (tRun) {   // only the timer is on screen
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { if (!e.isAutoRepeat) timerEnter(); e.accepted = true }
      else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) { tmr.add(e.key === Qt.Key_Up ? 5 : -5); e.accepted = true }
      return
    }
    if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9 && !!pt) { if (!editing) startEdit(String(e.key - Qt.Key_0)); e.accepted = true; return }
    if (e.key === Qt.Key_Right || e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
      const k = e.key;
      if (onTimer && (k === Qt.Key_Up || k === Qt.Key_Down)) tmr.add(k === Qt.Key_Up ? 5 : -5)
      else if (idx < 0) idx = 0
      else if (onTimer) { if (k === Qt.Key_Right) idx = 0 }
      else {   // spatial
        const d = nav[idx][k === Qt.Key_Left ? "l" : k === Qt.Key_Right ? "r" : k === Qt.Key_Up ? "u" : "d"]
        if (d >= 0) idx = d
      }
      e.accepted = true
    }
    else if (e.key === Qt.Key_Tab && onTimer) { tmr.setAction(tAct === "sleep" ? "poweroff" : "sleep"); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
      if (!e.isAutoRepeat && idx >= 0) { if (onTimer) timerEnter(); else press(items[idx]) }
      e.accepted = true
    }
  }
  Keys.onReleased: e => { if (!e.isAutoRepeat && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) { release(); e.accepted = true } }

  component Bracket: MouseArea {   // a quiet text button of the timer
    id: bb
    property string text
    property color tone: Theme.text
    property bool on: true
    implicitWidth: bl.implicitWidth + 16; implicitHeight: Math.round(22 * Theme.scale)
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; color: bb.containsMouse ? Theme.fillHover : "transparent" }
    Text { id: bl; anchors.centerIn: parent; text: bb.text
           font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
           color: bb.on ? bb.tone : Theme.dim }
  }

  component Plate: MouseArea {   // a plate button like START / the launcher's tiles: neutral 5 % tint, hover = fillHover, no outline
    id: pb
    property string text
    property color tone: Theme.text
    property bool square: false     // the -5 / +5 squares beside the countdown
    property bool wide: false       // fills the row (pause / cancel)
    Layout.preferredWidth: square ? Math.round(28 * Theme.scale) : 0
    Layout.preferredHeight: Math.round((square ? 28 : 24) * Theme.scale)
    Layout.fillWidth: wide
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    Rectangle { anchors.fill: parent; radius: Theme.radiusCtl
                color: pb.containsMouse ? Theme.fillHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05) }
    Text { anchors.centerIn: parent; text: pb.text; color: pb.tone
           font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  }

  // ---- idle: the timer on the left, the power rectangle on the right ----------------------------------------------------------------
  RowLayout {
    visible: !p.tRun
    Layout.fillWidth: true
    spacing: Math.round(14 * Theme.scale)

    ColumnLayout {   // LEFT: the timer setup, packed to the height of the plates (no caption, no gaps to fill)
      visible: !!p.pt
      Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
      Layout.preferredWidth: 1
      spacing: Math.round(8 * Theme.scale)
      RowLayout {   // the minutes (dot font; click = type a number) on the left, the action to the right of them
        Layout.fillWidth: true; Layout.preferredHeight: Math.round(28 * Theme.scale)
        spacing: Math.round(8 * Theme.scale)
        Item {   // the number + its unit
          id: heroBox
          Layout.preferredWidth: heroItem.width + 5 + heroUnit.implicitWidth; Layout.fillHeight: true
          Item {
            id: heroItem
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(heroText.implicitWidth, heroEdit.visible ? heroEdit.contentWidth + 4 : 0); height: heroText.implicitHeight
            Text { id: heroText; visible: !p.editing
                   text: String(p.dragMin >= 0 ? p.dragMin : tmr.nextMinutes); color: Theme.text
                   font.family: Theme.dot; font.pixelSize: Math.round(26 * Theme.scale); font.features: { "tnum": 1 }; font.hintingPreference: Font.PreferNoHinting }
            TextInput {
              id: heroEdit
              visible: p.editing
              width: Math.max(contentWidth + 4, Math.round(26 * Theme.scale)); height: parent.height
              color: Theme.accent; selectionColor: Theme.accent; selectedTextColor: Theme.surface
              font.family: Theme.dot; font.pixelSize: Math.round(26 * Theme.scale); font.features: { "tnum": 1 }
              maximumLength: 3; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 1; top: 999 }
              onAccepted: p.endEdit(true)
              onActiveFocusChanged: if (!activeFocus && p.editing) p.endEdit(true)
              Keys.onEscapePressed: e => { p.endEdit(false); e.accepted = true }
            }
            MouseArea { anchors.fill: parent; visible: !p.editing; cursorShape: Qt.IBeamCursor; onClicked: p.startEdit("") }
          }
          UiCaption {   // "min" sits on the number's baseline
            id: heroUnit; text: "min"
            x: heroItem.x + heroItem.width + 5
            y: heroItem.y + heroText.baselineOffset - baselineOffset
          }
        }
        Item { Layout.fillWidth: true }
        Rectangle {   // the action: a small segmented plate, SLEEP | OFF (the chosen one lifts)
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: Math.round(46 * Theme.scale); implicitHeight: Math.round(36 * Theme.scale)
          radius: Theme.radiusCtl; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
          Column {
            anchors { fill: parent; margins: 2 }
            spacing: 2
            Repeater {
              model: [["sleep", "Sleep"], ["poweroff", "Off"]]
              MouseArea {
                required property var modelData
                width: parent.width; height: (parent.height - 2) / 2
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: tmr.setAction(modelData[0])
                Rectangle { anchors.fill: parent; radius: Math.max(0, Theme.radiusCtl - 2)
                            color: p.tAct === modelData[0] ? Theme.fillHover : (parent.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05) : "transparent") }
                Text { anchors.centerIn: parent; text: modelData[1]; color: p.tAct === modelData[0] ? Theme.text : Theme.dim
                       font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(9 * Theme.scale) }
              }
            }
          }
        }
      }
      Item {   // the track: drag to set, wheel = +-5 min
        Layout.fillWidth: true; Layout.preferredHeight: Math.round(12 * Theme.scale)
        DotMeter { anchors.verticalCenter: parent.verticalCenter; width: parent.width; fit: width; dotSize: 3; gap: 3
                   value: Math.min(1, (p.dragMin >= 0 ? p.dragMin : tmr.nextMinutes) / 120); litColor: Theme.text }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onEntered: p.idx = p.timerIdx
          onPressed: m => p.dragTo(m.x / width)
          onPositionChanged: m => { if (pressed) p.dragTo(m.x / width) }
          onReleased: p.commitDrag()
          onCanceled: p.dragMin = -1
          onWheel: w => tmr.add(w.angleDelta.y > 0 ? 5 : -5)
        }
      }
      MouseArea {   // START: a plate like the tiles, fills the rest of the height
        id: startBtn
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: Math.round(24 * Theme.scale)
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: tmr.start()
        Rectangle { anchors.fill: parent; radius: Theme.radiusCtl
                    color: startBtn.containsMouse || p.idx === p.timerIdx ? Theme.fillHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05) }
        Text { anchors.centerIn: parent; text: "Start"; color: Theme.text
               font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale) }
      }
    }

    Item {   // RIGHT: four SEPARATE plates in a 2x2 grid (the launcher's tile look): Lock (instant) Sleep / Reboot Power off (held)
      id: pr
      Layout.fillWidth: !p.pt; Layout.alignment: Qt.AlignTop
      Layout.preferredWidth: p.pt ? Math.round(82 * Theme.scale) : -1
      implicitHeight: Math.round(82 * Theme.scale)
      GridLayout {
        id: grid
        anchors.fill: parent
        columns: 2; rowSpacing: Math.round(6 * Theme.scale); columnSpacing: Math.round(6 * Theme.scale)
        Repeater {
          model: p.items
          MouseArea {
            id: cell
            required property var modelData
            required property int index
            readonly property bool picked: p.idx === index
            readonly property bool holdingMe: p.holding === modelData.id
            Layout.preferredWidth: Math.round(38 * Theme.scale); Layout.preferredHeight: Math.round(38 * Theme.scale)   // square, the launcher tile's height
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onEntered: p.idx = index
            onPressed: p.press(modelData)
            onReleased: p.release()
            onCanceled: p.release()
            Rectangle {   // the plate: a neutral 5 % tint like the launcher's tiles, hover / picked = fillHover; hold: a red sweep behind the icon
              anchors.fill: parent; radius: Theme.radiusCtl; clip: true
              color: cell.containsMouse || cell.picked ? Theme.fillHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
              Rectangle { visible: cell.holdingMe; width: parent.width * p.holdP; height: parent.height
                          color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25) }
            }
            DotGlyph {   // the icon only: centred, no caption, no lift
              anchors.centerIn: parent
              name: cell.modelData.id
              dot: 2; gap: 1
              level: cell.picked ? 1 : 0.9
              progress: cell.holdingMe ? p.holdP : 0
            }
          }
        }
      }
    }
  }

  // ---- running / paused: the timer takes the whole drop ---------------------------------------------------------------------------
  ColumnLayout {
    id: runCol
    visible: p.tRun
    Layout.fillWidth: true
    spacing: 6
    RowLayout {
      Layout.fillWidth: true
      UiCaption { text: "Timer · " + tmr.label(tmr.paused ? tmr.pausedAction : tmr.action); color: Theme.text }
      Item { Layout.fillWidth: true }
      UiCaption { text: tmr.paused ? "paused" : "at " + Qt.formatTime(new Date(tmr.until), "HH:mm"); color: tmr.paused ? Theme.accent : Theme.dim }
    }
    RowLayout {   // -5 | the countdown | +5
      Layout.fillWidth: true; spacing: 6
      Plate { text: "-5"; square: true; onClicked: tmr.add(-5) }
      Item {
        Layout.fillWidth: true; Layout.preferredHeight: Math.round(36 * Theme.scale)
        Text {   // the countdown, big
          anchors.centerIn: parent
          text: tmr.paused ? tmr.clock(tmr.pausedSec) : tmr.leftText
          color: Theme.text; opacity: tmr.paused ? 0.5 : 1
          font.family: Theme.dot; font.pixelSize: Math.round(36 * Theme.scale); font.features: { "tnum": 1 }; font.hintingPreference: Font.PreferNoHinting
        }
      }
      Plate { text: "+5"; square: true; onClicked: tmr.add(5) }
    }
    DotMeter {   // the track drains with the time
      Layout.fillWidth: true; fit: width; dotSize: 3; gap: 3
      value: tmr.paused ? Math.min(1, tmr.pausedSec / Math.max(1, tmr.pausedTotal * 60)) : tmr.progress
      litColor: tmr.paused ? Theme.dim : Theme.accent
    }
    RowLayout {   // pause and cancel: plates like START
      Layout.fillWidth: true; spacing: 6
      Plate { text: tmr.paused ? "Resume" : "Pause"; wide: true; onClicked: tmr.paused ? tmr.resume() : tmr.pause() }
      Plate { text: "Cancel"; wide: true; tone: Theme.red; onClicked: tmr.cancel() }
    }
  }
}
