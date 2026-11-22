// Cycle row (drop panels): pick one of N things in ONE line - caption, glyph, current name, a pager (dots up to 6, "3/9" beyond), chevrons.
// Click / Enter / → = next, right click / ← = previous, wheel steps. The owner maps `step(d)` to its list; it never grows with the count.
// `caption`, `icon`, `text`, `count`, `index`, `focused` (keys; panelkeys), `step(d)`.
import QtQuick
import QtQuick.Layouts
import qs.core

MouseArea {
  id: c
  property string caption
  property string icon
  property string text
  property int count: 0
  property int index: 0
  property bool focused: false
  signal step(int d)
  property int dir: 1             // last step direction: the new name slides in from that side
  Connections { target: c; function onStep(d) { c.dir = d } }
  signal act()
  function nudge(d) { step(d > 0 ? 1 : -1) }   // panelkeys: ← →
  onAct: step(1)
  Layout.fillWidth: true; implicitHeight: 28
  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: m => step(m.button === Qt.RightButton ? -1 : 1)
  onWheel: w => step(w.angleDelta.y > 0 ? -1 : 1)
  Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: c.focused ? Theme.fillHover : c.containsMouse ? Theme.fill : "transparent" }
  RowLayout {
    anchors { fill: parent; leftMargin: 4; rightMargin: 4 } spacing: 8
    Text { text: c.caption; color: Theme.dim; Layout.preferredWidth: Math.round(84 * Theme.scale)
           font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
    Item {   // glyph + name change together: the old one slips out, the new one slides in from the step direction
      id: face
      Layout.fillWidth: true; implicitHeight: nameT.implicitHeight; clip: true
      property string shownText: c.text
      property string shownIcon: c.icon
      Connections { target: c; function onTextChanged() { swap.restart() } function onIconChanged() { swap.restart() } }
      SequentialAnimation {
        id: swap
        ParallelAnimation {
          NumberAnimation { target: row; property: "opacity"; to: 0; duration: Motion.off ? 0 : 70 }
          NumberAnimation { target: row; property: "x"; to: -10 * c.dir; duration: Motion.off ? 0 : 70 }
        }
        ScriptAction { script: { face.shownText = c.text; face.shownIcon = c.icon; row.x = 12 * c.dir } }
        ParallelAnimation {
          NumberAnimation { target: row; property: "opacity"; to: 1; duration: Motion.off ? 0 : 130; easing.type: Easing.OutCubic }
          NumberAnimation { target: row; property: "x"; to: 0; duration: Motion.off ? 0 : 130; easing.type: Easing.OutCubic }
        }
      }
      Row {
        id: row
        spacing: 8; width: parent.width
        Icon { name: face.shownIcon; visible: face.shownIcon !== ""; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
        Text { id: nameT; text: face.shownText; color: Theme.text; elide: Text.ElideRight; width: parent.width - (face.shownIcon !== "" ? 28 : 0)
               font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); anchors.verticalCenter: parent.verticalCenter }
      }
    }
    Row {   // pager
      visible: c.count > 1; spacing: 3; Layout.alignment: Qt.AlignVCenter
      Repeater { model: c.count <= 6 ? c.count : 0
                 Rectangle { required property int index; width: 4; height: 4; radius: 2; color: Theme.text; opacity: index === c.index ? 1 : 0.16
                             Behavior on opacity { NumberAnimation { duration: Motion.off ? 0 : 120 } } } }
      Text { visible: c.count > 6; text: (c.index + 1) + "/" + c.count; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale) }
    }
    Icon { name: "caret-right"; visible: c.count > 1; color: Theme.dim }
  }
}
