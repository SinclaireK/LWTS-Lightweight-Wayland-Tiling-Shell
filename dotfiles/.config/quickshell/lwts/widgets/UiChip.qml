// Quiet text switch (launcher v2): a mono-caps label, bright when on, dim when off; no box, no dot. Click / Enter = act, right click = details.
// `focusedChip` = keyboard focus (ring), `hint` = the Alt-letter shown instead of the label while Alt is held.
import QtQuick
import qs.core

MouseArea {
  id: c
  property string text
  property bool on: false
  property bool focusedChip: false
  property string hint: ""
  signal act()
  signal details()
  property int padX: 8
  implicitWidth: lbl.implicitWidth + padX * 2
  implicitHeight: Math.round(20 * Theme.scale)
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: m => m.button === Qt.RightButton ? details() : act()
  Rectangle {
    anchors { fill: parent; margins: 1 }
    radius: Theme.radiusCtl
    color: c.containsMouse ? Theme.fillHover : "transparent"
    border.width: c.focusedChip ? 2 : 0; border.color: Theme.ring
    Behavior on color { ColorAnimation { duration: Motion.duration } }
  }
  Text {
    id: lbl
    anchors.centerIn: parent
    width: parent.width - 4; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
    text: c.hint !== "" ? c.hint : c.text
    color: c.hint !== "" ? Theme.accent : c.on ? Theme.text : Theme.dim
    opacity: c.on || c.hint !== "" ? 1 : 0.7
    font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
    font.weight: c.hint !== "" ? Font.Bold : Font.Normal
    Behavior on color { ColorAnimation { duration: Motion.duration } }
  }
}
