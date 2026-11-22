// Legend for GamepadView: hollow dot = the hand, solid dot = what games get.
import QtQuick
import qs.core

Row {
  spacing: 6
  Rectangle { width: 8; height: 8; radius: 4; color: "transparent"; border.width: 1.5; border.color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
  Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale); text: "Hand"; anchors.verticalCenter: parent.verticalCenter }
  Item { width: 6; height: 1 }
  Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
  Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale); text: "Game"; anchors.verticalCenter: parent.verticalCenter }
}
