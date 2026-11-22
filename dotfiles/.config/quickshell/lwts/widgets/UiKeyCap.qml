// A dim keycap: shows the key that does what its row does (Settings -> Layout inspector). `k` = the key text.
import QtQuick
import qs.core

Rectangle {
  property string k: ""
  implicitWidth: Math.max(18, label.implicitWidth + 8); implicitHeight: 16; radius: 3
  color: "transparent"; border.width: 1; border.color: Theme.line
  Text { id: label; anchors.centerIn: parent; text: parent.k; color: Theme.dim; font.family: Theme.label; font.pixelSize: 9 }
}
