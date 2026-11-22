// Knobless slider (settings_spec 1.3): a flat filled track, never a thumb; the value with its unit on the right.
// Discrete grid: `steps` (e.g. [0, 3, 6, 8, 12]) - click / drag snaps to the nearest one, ← → / wheel walk the grid.
// Empty `steps` = continuous from..to by stepSize. Emits moved(value) only; the owner writes it and binds `value` back.
// In Settings the page forwards keys itself: set `highlighted` and call stepBy(±1).
import QtQuick
import qs.core

Item {
  id: s
  property real value: 0
  property var steps: []
  property real from: 0
  property real to: 1
  property real stepSize: 0.05
  property string unit: ""                 // "px", "%", "K" ...
  property var format: null                // optional v => text, wins over unit
  property bool highlighted: activeFocus
  signal moved(real value)

  implicitHeight: Math.round(20 * Theme.scale)
  implicitWidth: 200
  activeFocusOnTab: true

  readonly property real lo: steps.length ? Math.min(...steps) : from
  readonly property real hi: steps.length ? Math.max(...steps) : to
  readonly property real frac: hi > lo ? Math.max(0, Math.min(1, (value - lo) / (hi - lo))) : 0
  readonly property string text: format ? format(value) : (+value.toFixed(2)) + (unit ? (unit === "%" ? "%" : " " + unit) : "")

  function snap(v) {
    if (steps.length) return steps.reduce((a, b) => Math.abs(b - v) < Math.abs(a - v) ? b : a);
    return Math.max(from, Math.min(to, from + Math.round((v - from) / stepSize) * stepSize));
  }
  function setAt(x) { const v = snap(lo + Math.max(0, Math.min(1, x / track.width)) * (hi - lo)); if (v !== value) moved(v) }
  function stepBy(d) {
    if (steps.length) {
      const sorted = steps.slice().sort((a, b) => a - b), i = sorted.indexOf(snap(value));
      const v = sorted[Math.max(0, Math.min(sorted.length - 1, i + d))];
      if (v !== value) moved(v);
    } else { const v = snap(value + d * stepSize); if (v !== value) moved(v) }
  }

  Keys.onLeftPressed: stepBy(-1)
  Keys.onRightPressed: stepBy(1)

  Rectangle {
    id: track
    anchors { left: parent.left; right: valueText.left; rightMargin: Math.round(10 * Theme.scale); verticalCenter: parent.verticalCenter }
    height: Math.round(6 * Theme.scale)
    color: "transparent"   // geometry only; the dots draw the track
    DotMeter {   // Nothing style: dots instead of the filled bar
      anchors.verticalCenter: parent.verticalCenter
      fit: parent.width; dotSize: 4; gap: 3
      value: s.frac
      litColor: Theme.accent
    }
  }
  MouseArea {
    id: area
    anchors { fill: track; topMargin: -6; bottomMargin: -6 }   // easier to hit than the thin track
    cursorShape: Qt.PointingHandCursor
    onPressed: m => { s.forceActiveFocus(); s.setAt(m.x) }
    onPositionChanged: m => { if (pressed) s.setAt(m.x) }
    onWheel: w => s.stepBy(w.angleDelta.y > 0 ? 1 : -1)
  }
  Text {
    id: valueText
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    width: Math.round(52 * Theme.scale); horizontalAlignment: Text.AlignRight
    text: s.text
    color: s.highlighted ? Theme.accent : Theme.text
    font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); font.features: { "tnum": 1 }
  }
}
