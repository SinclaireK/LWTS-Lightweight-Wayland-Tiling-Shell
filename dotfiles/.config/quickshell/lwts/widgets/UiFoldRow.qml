// Fold row (drop panels): mono caps title, an optional dim value, a caret; click / Enter opens or closes a block under it.
// `text`, `value`, `glyphs` (icons), `glyph` (link row), `open`, `focused` (keys; panelkeys finds it by `focused` + `act`), `act()` (default: nothing - the owner flips `open`).
import QtQuick
import QtQuick.Layouts
import qs.core

MouseArea {
  id: f
  property string text
  property string value: ""
  property bool open: false
  property var glyphs: []           // small icons before the caret instead of / next to the value (what is current, no text to squeeze)
  property string glyph: ""        // a link row: this icon instead of the caret (e.g. arrow-up-right = opens Settings)
  property bool focused: false
  signal act()
  Layout.fillWidth: true; implicitHeight: 28
  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
  onClicked: act()
  Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: f.focused ? Theme.fillHover : f.containsMouse ? Theme.fill : "transparent" }
  RowLayout {
    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
    Text { text: f.text; color: f.open ? Theme.text : Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
    Item { Layout.fillWidth: true }
    Text { text: f.value; visible: f.value !== ""; color: Theme.dim; elide: Text.ElideRight; Layout.maximumWidth: Math.round(200 * Theme.scale)
           font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale) }
    Row { spacing: 8; visible: f.glyphs.length > 0; Repeater { model: f.glyphs; Icon { required property string modelData; name: modelData; color: Theme.text } } }
    Icon { name: f.glyph !== "" ? f.glyph : f.open ? "caret-up" : "caret-down"; color: Theme.dim }
  }
}
