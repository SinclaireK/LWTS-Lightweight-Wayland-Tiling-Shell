// Rail item (Tasks): glyph + mono caps label; `on` = white outline; `link` = a trailing arrow (opens another place). Click = `clicked`.
import QtQuick
import QtQuick.Layouts
import qs.core

MouseArea {
  id: ni
  property string label
  property string glyph
  property bool on: false
  property bool link: false
  property bool compact: false   // icon only (a narrow rail)
  Layout.fillWidth: true; implicitHeight: 32; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
  Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"; border.width: ni.on ? 1 : 0; border.color: Theme.text }
  Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover; visible: !ni.on && ni.containsMouse }
  Row {
    anchors.left: ni.compact ? undefined : parent.left; anchors.leftMargin: 10; anchors.horizontalCenter: ni.compact ? parent.horizontalCenter : undefined; anchors.verticalCenter: parent.verticalCenter; spacing: 8
    Icon { anchors.verticalCenter: parent.verticalCenter; name: ni.glyph; color: ni.on ? Theme.text : Theme.dim; font.pixelSize: 15 }
    UiCaption { visible: !ni.compact; anchors.verticalCenter: parent.verticalCenter; text: ni.label; color: ni.on ? Theme.text : Theme.dim; font.pixelSize: Math.round(11 * Theme.scale) }
  }
  Icon { visible: ni.link; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "arrow-up-right"; color: Theme.dim; font.pixelSize: 13 }
}
