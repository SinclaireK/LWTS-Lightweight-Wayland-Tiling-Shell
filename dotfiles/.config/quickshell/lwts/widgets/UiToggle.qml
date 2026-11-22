// Switch (Nothing): a 6 px rounded track with a square-ish knob; accent track + accentInk knob when on, the knob slides.
// The one definition: Settings rows, pickers. API: `on`, `focusedChip` (keyboard highlight), `clicked` (MouseArea).
// The hit area keeps the 24 px row height; the track is 16 px, centred. Square rounding preset -> square track.
import QtQuick
import qs.core

MouseArea {
  id: sw
  property bool on: false
  property bool focusedChip: false
  implicitWidth: Math.round(32 * Theme.scale); implicitHeight: 24
  cursorShape: Qt.PointingHandCursor
  hoverEnabled: true
  Rectangle {
    id: track
    anchors.centerIn: parent
    width: parent.width; height: Math.round(16 * Theme.scale)
    radius: Math.min(Theme.radiusCtl, height / 2)
    color: sw.containsMouse ? Theme.fillHover : "transparent"   // Nothing: always an outline; on = white outline + the red knob
    border.width: sw.focusedChip ? 2 : 1; border.color: sw.focusedChip ? Theme.ring : sw.on ? Theme.text : Theme.edge
    Behavior on color { ColorAnimation { duration: Motion.duration } }
    Rectangle {
      id: knob
      width: track.height - 6; height: width; y: 3
      radius: Math.min(Theme.radiusCtl / 2, width / 2)   // a small rounded square knob, like the track
      x: sw.on ? track.width - width - 3 : 3
      color: sw.on ? Theme.red : Theme.dim
      Behavior on x { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
      Behavior on color { ColorAnimation { duration: Motion.duration } }
    }
  }
}
