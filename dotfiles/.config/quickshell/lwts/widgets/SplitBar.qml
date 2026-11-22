// Split bar: one track shared between segments by their size. `segs` = [{ w: size, a: opacity 0..1 }, ...]; the track is their sum.
// Monochrome on purpose (Nothing: one accent): the segments differ by the text colour's opacity, the legend names them.
import QtQuick
import qs.core

Item {
  id: sb
  property var segs: []
  readonly property real total: segs.reduce((s, x) => s + x.w, 0)
  implicitHeight: 8
  property int glide: 1800   // readings come every 2 s: the segments glide on to the next one instead of stepping (data smoothing, not UI motion)
  Row {
    anchors.fill: parent
    spacing: 2
    Repeater {
      model: sb.segs.length   // a count, not the array: the delegates survive every new reading, so Behavior can animate
      Rectangle {
        required property int index
        readonly property var seg: sb.segs[index] || ({ w: 0, a: 1 })
        height: parent.height; radius: 2
        width: sb.total > 0 ? Math.max(0, (sb.width - (sb.segs.length - 1) * 2) * seg.w / sb.total) : 0
        color: Theme.text; opacity: seg.a
        Behavior on width { enabled: !Motion.off; NumberAnimation { duration: sb.glide; easing.type: Easing.OutCubic } }
      }
    }
  }
}
