// A palette family (dark | light side by side) or one theme, with its name underneath (palette picker)
import QtQuick
import qs.core

Rectangle {   // a family (dark | light) or one theme, with its name underneath
  property var item: null
  property bool current: false
  radius: Theme.radius
  color: Theme.surface
  Row {
    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: parent.height - 24
    Repeater {
      model: item ? item.pals : []
      PaletteHalf {
        required property int index
        required property var modelData
        pal: modelData
        width: parent.width / (item ? item.pals.length : 1); height: parent.height
        inner: item && item.pals.length > 1 ? (index === 0 ? "right" : "left") : ""
      }
    }
  }
  Text { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
         text: item ? item.label : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); font.weight: Font.DemiBold; elide: Text.ElideRight }
  Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"
              border.width: current ? 2 : 1; border.color: current ? Theme.accent : Theme.line }
}
