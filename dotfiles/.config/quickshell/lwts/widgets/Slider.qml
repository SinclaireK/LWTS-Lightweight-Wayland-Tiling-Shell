// Dot slider (Nothing style): a row of 4px dots, accent where lit; the thumb shows only on hover / drag (LWTS_SPEC 1). Wheel steps 5%.
import QtQuick
import qs.core

MouseArea {
  id: s
  property real value: 0          // 0..maxv (maxv 1 = a normal volume; 1.5 = boost: dots past 100% are red)
  property real maxv: 1
  property bool wave: false       // dots light in a quick wave instead of all at once (not while dragging)
  property real dotSize: 4
  property real gap: 3
  signal moved(real value)
  implicitHeight: 16
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  function at(x) { return Math.max(0, Math.min(1, x / width)) * maxv }
  onPressed: m => moved(at(m.x))
  onPositionChanged: m => { if (pressed) moved(at(m.x)) }
  onWheel: w => moved(Math.max(0, Math.min(maxv, value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))

  DotMeter {   // Nothing style: the track is a row of dots (lit = accent), the same size at any width
    anchors.verticalCenter: parent.verticalCenter
    fit: parent.width; dotSize: s.dotSize; gap: s.gap
    value: s.value / s.maxv; wave: s.wave && !s.pressed
    litColor: Theme.accent
    hot: s.maxv > 1 ? 1 / s.maxv + 0.001 : 2; hotColor: Theme.red
  }
  Rectangle {   // thumb
    width: 12; height: 12; radius: 6
    anchors.verticalCenter: parent.verticalCenter
    x: s.width * s.value / s.maxv - width / 2
    color: Theme.accent
    opacity: s.containsMouse || s.pressed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.duration } }
  }
}
