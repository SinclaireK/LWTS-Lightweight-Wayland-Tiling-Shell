// Alt-letter badge (accent square + letter), the same look as UiKvRow's hint. Hidden while `letter` is empty.
import QtQuick
import qs.core

Rectangle {
  property string letter: ""
  visible: letter !== ""
  implicitWidth: 14; implicitHeight: 14; radius: 3; color: Theme.accent
  Text { anchors.centerIn: parent; text: parent.letter; color: Theme.surface; font.family: Theme.label; font.pixelSize: 9; font.weight: Font.Bold }
}
