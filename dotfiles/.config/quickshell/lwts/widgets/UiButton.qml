// Button / chip (Nothing: 6 px rectangle, mono capitals): filled (accent when `on`), the same highlight for mouse and keys (`focusedChip`). The one definition for chips and buttons.
import QtQuick
import qs.core

MouseArea {
  id: b
  property string text
  property bool on: false
  property bool focusedChip: false
  property bool flat: false          // no fill at rest (a chip inside a joined group)
  property real padX: 14
  implicitWidth: label.implicitWidth + padX; implicitHeight: 22
  cursorShape: Qt.PointingHandCursor
  hoverEnabled: true
  Rectangle { anchors.fill: parent; radius: Theme.radiusCtl
              readonly property bool hot: b.containsMouse || b.focusedChip
              color: b.on ? (hot ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.86) : Theme.accent) : hot ? Theme.fillHover : "transparent"
              border.width: b.on || b.flat ? 0 : 1; border.color: hot ? Theme.dim : Theme.edge   // Nothing: outlined at rest, solid when on
              Behavior on color { ColorAnimation { duration: Motion.duration } } }
  Text { id: label; anchors.centerIn: parent; text: b.text; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
         color: b.on ? Theme.accentInk : Theme.text
         Behavior on color { ColorAnimation { duration: Motion.duration } } }
}
