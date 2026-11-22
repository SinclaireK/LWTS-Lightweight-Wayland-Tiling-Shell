// One list row for panels (`led` = the drop-panel hand: a LED dot instead of the icon / tint, mono caps trail, optional dot `meter`): icon, title, optional subtitle, optional right text. on = current / connected
// (accent icon + tint); focused = keyboard focus (stronger fill, no frame). Click = act, right click = alt.
import QtQuick
import Quickshell.Widgets
import qs.core

MouseArea {
  id: r
  property string icon
  property string iconSource: ""   // a real image (an app icon) instead of the Phosphor glyph
  property string title
  property string sub: ""
  property string trail: ""
  property bool on: false
  property bool focused: false
  property bool led: false         // panel-style row: lit LED = current / connected, no tint plate, 28 px
  property real meter: -1          // led rows: 0..1 = a 5-dot meter before the trail (battery), -1 = none
  signal act()
  signal alt()
  implicitHeight: led ? 28 : sub ? 46 : 36   // Nothing: airy rows
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: m => m.button === Qt.RightButton ? alt() : act()
  Rectangle {
    anchors.fill: parent; radius: Theme.radiusInner
    color: r.led ? (r.focused ? Theme.fillHover : r.containsMouse ? Theme.fill : "transparent")
         : r.on ? (r.focused ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) : Theme.tint)
         : r.focused ? Theme.fillHover : r.containsMouse ? Theme.fill : "transparent"
  }
  Rectangle { id: dot; visible: r.led; width: 5; height: 5; radius: 2.5; color: Theme.text; opacity: r.on ? 1 : 0.16
              anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
  AppIcon { id: pic; visible: r.iconSource !== ""; source: r.iconSource; size: 16
              anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
  Icon { id: ic; visible: !r.led && r.icon !== "" && r.iconSource === ""; name: r.icon; fill: r.on; color: r.on ? Theme.accent : Theme.text
         anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
  Column {
    anchors { left: r.led ? dot.right : pic.visible ? pic.right : ic.visible ? ic.right : parent.left; leftMargin: 9; right: dm.visible ? dm.left : rt.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
    Text { width: parent.width; elide: Text.ElideRight; text: r.title; color: Theme.text; opacity: r.led && !r.on ? 0.75 : 1; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
    Text { visible: r.sub !== ""; width: parent.width; elide: Text.ElideRight; text: r.sub; color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(10 * Theme.scale) }
  }
  DotMeter { id: dm; visible: r.led && r.meter >= 0; count: 5; dotSize: 3; value: Math.max(0, r.meter); hot: 2
             anchors { right: rt.left; rightMargin: 8; verticalCenter: parent.verticalCenter } }
  Text { id: rt; anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
         text: r.trail; color: Theme.dim; font.family: r.led ? Theme.label : Theme.font; font.capitalization: r.led ? Font.AllUppercase : Font.MixedCase
         font.pixelSize: Math.round((r.led ? 10 : 11) * Theme.scale) }
}
