// Stepped slider (the Windows power-mode flyout): a thin track with a dot per stop and one thumb that snaps to the nearest stop.
// `stops` = [[id, "Label"], ...], `current` = the id; `dim` = the value is inferred (a hollow thumb). Click / drag picks; as a panel row it
// takes the keyboard like the other rows (`focused`, `act`, `nudge(d)`: ← → move one stop, see popups/panelkeys.js).
import QtQuick
import qs.core

Item {
  id: s
  property var stops: []
  property string current
  property bool dim: false
  property bool focused: false
  signal picked(string id)
  signal act()
  readonly property int idx: Math.max(0, stops.findIndex(x => x[0] === current))
  readonly property real pad: 10
  function xAt(i) { return pad + (width - 2 * pad) * i / Math.max(1, stops.length - 1) }
  function nudge(d) { const i = Math.max(0, Math.min(stops.length - 1, idx + (d > 0 ? 1 : -1))); if (i !== idx || dim) picked(stops[i][0]) }
  implicitHeight: 52
  Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover; opacity: s.focused ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Motion.fast } } }
  Rectangle { x: s.pad; y: 15; width: s.width - 2 * s.pad; height: 2; radius: 1; color: Theme.line }
  Repeater {
    model: s.stops.length
    Rectangle { required property int index; x: s.xAt(index) - 3; y: 13; width: 6; height: 6; radius: 3; color: index <= s.idx ? Theme.text : Theme.dim }
  }
  Rectangle {   // the thumb
    id: thumb
    width: 14; height: 14; radius: 7; y: 9
    x: s.xAt(s.idx) - 7
    color: s.dim ? Theme.surface : Theme.text; border.width: s.dim ? 2 : 0; border.color: Theme.text
    Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
  }
  Repeater {
    model: s.stops.length
    Text {
      required property int index
      text: s.stops[index][1]
      color: index === s.idx ? Theme.text : Theme.dim
      font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
      y: 32
      x: Math.max(0, Math.min(s.width - implicitWidth, s.xAt(index) - implicitWidth / 2))
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    function pick(mx) {
      let best = 0, d = 1e9;
      for (let i = 0; i < s.stops.length; i++) { const e = Math.abs(mx - s.xAt(i)); if (e < d) { d = e; best = i } }
      if (best !== s.idx || s.dim) s.picked(s.stops[best][0]);
    }
    onClicked: m => pick(m.x)
    onPositionChanged: m => { if (pressed) pick(m.x) }
  }
}
