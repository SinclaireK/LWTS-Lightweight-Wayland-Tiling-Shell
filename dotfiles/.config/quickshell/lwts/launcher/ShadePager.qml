// Page switch in the launcher header (between the date and the time): "<  QUICK SETTINGS  >" + one dot per page (Nothing: mono caps, 4 px dots,
// the current one lit, the rest 0.16). Click an arrow / wheel / Tab / Shift+Tab step through the pages; the name slides in from the step side.
// Pages of the drop: Quick settings, Notifications (+ calendar), Notes.
import QtQuick
import qs.core
import qs.widgets

Item {
  id: p
  property string text: ""
  property int count: 0
  property int index: 0
  signal step(int d)
  implicitHeight: 28
  property int dir: 1
  Connections { target: p; function onStep(d) { p.dir = d } }
  property string shown: text
  onTextChanged: swap.restart()
  SequentialAnimation {
    id: swap
    ParallelAnimation {
      NumberAnimation { target: face; property: "opacity"; to: 0; duration: Motion.off ? 0 : 70 }
      NumberAnimation { target: face; property: "x"; to: -10 * p.dir; duration: Motion.off ? 0 : 70 }
    }
    ScriptAction { script: { p.shown = p.text; face.x = 12 * p.dir } }
    ParallelAnimation {
      NumberAnimation { target: face; property: "opacity"; to: 1; duration: Motion.off ? 0 : 130; easing.type: Easing.OutCubic }
      NumberAnimation { target: face; property: "x"; to: 0; duration: Motion.off ? 0 : 130; easing.type: Easing.OutCubic }
    }
  }
  WheelHandler { onWheel: e => p.step(e.angleDelta.y > 0 ? -1 : 1) }
  readonly property real arrowW: 18
  readonly property real gapW: 4
  readonly property real nameW: Math.max(40, Math.min(Math.round(150 * Theme.scale), p.width - 2 * arrowW - 2 * gapW))   // the gap between the date and the time can be narrow (launcher): the name shrinks, the arrows stay
  Row {
    anchors.centerIn: parent
    spacing: p.gapW
    MouseArea {
      anchors.verticalCenter: parent.verticalCenter
      width: p.arrowW; height: 24; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: p.step(-1)
      Icon { anchors.centerIn: parent; name: "caret-left"; color: parent.containsMouse ? Theme.text : Theme.dim }
    }
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: p.nameW; height: p.implicitHeight
      clip: true
      Column {
        id: face
        width: parent.width; anchors.verticalCenter: parent.verticalCenter; spacing: 4
        UiCaption { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: p.shown; color: Theme.text; elide: Text.ElideRight }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: 3
          Repeater {
            model: p.count
            Rectangle { required property int index; width: 4; height: 4; radius: 2; color: Theme.text; opacity: index === p.index ? 1 : 0.16
                        Behavior on opacity { NumberAnimation { duration: Motion.off ? 0 : 120 } } }
          }
        }
      }
    }
    MouseArea {
      anchors.verticalCenter: parent.verticalCenter
      width: p.arrowW; height: 24; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: p.step(1)
      Icon { anchors.centerIn: parent; name: "caret-right"; color: parent.containsMouse ? Theme.text : Theme.dim }
    }
  }
}
