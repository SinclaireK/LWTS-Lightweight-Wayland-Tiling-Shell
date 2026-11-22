// One segment of a joined control (the selection is a sliding pill drawn by the owner under the row; hover = a light wash over it).
import QtQuick
import qs.core

MouseArea {
  id: g
  property string text
  property bool on: false
  property bool focusedChip: false
  implicitWidth: label.implicitWidth + 18; implicitHeight: 24
  cursorShape: Qt.PointingHandCursor
  hoverEnabled: true
  Rectangle { anchors { fill: parent; margins: 2 } radius: Theme.radiusCtl
              color: !(g.containsMouse || g.focusedChip) ? "transparent" : g.on ? Qt.rgba(1, 1, 1, 0.12) : Theme.fillHover   // keys get the same wash
              Behavior on color { ColorAnimation { duration: Motion.duration } } }
  Text { id: label; anchors.centerIn: parent; text: g.text; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
         verticalAlignment: Text.AlignVCenter
         color: g.on ? Theme.accentInk : Theme.text
         Behavior on color { ColorAnimation { duration: Motion.duration * 1.5 } } }
}
