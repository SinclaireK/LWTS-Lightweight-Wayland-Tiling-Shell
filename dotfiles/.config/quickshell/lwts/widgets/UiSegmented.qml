// Nothing segmented control: an outlined 1 px track + ONE accent pill that glides to the picked segment (same motion and look as the
// Settings "choice" rows). `options` = [[id, "Label"], ...], `current` = the picked id, signal picked(id). First show has no flight.
import QtQuick
import qs.core

Rectangle {
  id: sg
  property var options: []
  property var current
  signal picked(var id)
  implicitWidth: row.implicitWidth; implicitHeight: 24
  radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge

  Rectangle {
    id: pill
    readonly property int idx: sg.options.findIndex(o => String(sg.current) === String(o[0]))
    readonly property Item seg: (row.implicitWidth, idx >= 0 ? rep.itemAt(idx) : null)
    property bool live: false
    Component.onCompleted: Qt.callLater(() => live = true)
    visible: !!seg
    x: seg ? seg.x + 2 : 0; y: 2; width: seg ? seg.width - 4 : 0; height: parent.height - 4
    radius: Theme.radiusCtl; color: Theme.accent
    Behavior on x { enabled: pill.live; NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
    Behavior on width { enabled: pill.live; NumberAnimation { duration: Motion.dropOpen; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
  }
  Row {
    id: row
    Repeater {
      id: rep
      model: sg.options
      UiSeg {
        required property var modelData
        text: modelData[1]
        on: String(sg.current) === String(modelData[0])
        onClicked: sg.picked(modelData[0])
      }
    }
  }
}
