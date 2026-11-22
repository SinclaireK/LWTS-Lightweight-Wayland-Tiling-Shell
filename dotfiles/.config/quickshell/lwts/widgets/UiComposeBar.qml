// A dotted bar split into parts (memory: in use / cached / free): each dot belongs to one segment, lit at its own strength.
// segments: [{ v (share, any scale), a (opacity 0..1) }]. Fills its width.
import QtQuick
import qs.core

Item {
  id: b
  property var segments: []
  property real dotSize: 5
  property real gap: 3
  readonly property int n: Math.max(4, Math.floor((width + gap) / (dotSize + gap)))
  readonly property real total: segments.reduce((a, s) => a + Math.max(0, s.v), 0)
  implicitHeight: dotSize
  Row {
    spacing: (b.width - b.n * b.dotSize) / Math.max(1, b.n - 1)
    Repeater {
      model: b.n
      Rectangle {
        required property int index
        readonly property real pos: b.total > 0 ? (index + 0.5) / b.n * b.total : 0
        readonly property real al: { let c = 0; for (const s of b.segments) { c += Math.max(0, s.v); if (pos <= c) return s.a } return 0.16 }
        width: b.dotSize; height: b.dotSize; radius: width / 2; color: Theme.text; opacity: al
      }
    }
  }
}
