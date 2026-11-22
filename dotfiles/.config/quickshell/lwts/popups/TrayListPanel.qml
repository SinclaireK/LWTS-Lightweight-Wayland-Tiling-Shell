// Tray icons as a list (Quick settings "Tray" tile): the keyboard way to reach what the bar's right-click tray shows.
// Keys: ↑ ↓ pick, Enter = open the app (its menu if it has nothing else), → or Shift+Enter = its menu, Esc closes.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core
import qs.widgets

ColumnLayout {
  id: p
  spacing: 0
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  signal showMenu(var handle)
  property int hot: SystemTray.items.values.length ? 0 : -1
  readonly property int rowH: Math.round(Theme.barPx * 1.2)
  readonly property var list: SystemTray.items.values

  function open(it, menu) {
    if (!it) return;
    if (it.hasMenu && (menu || it.onlyMenu)) showMenu(it.menu);
    else { it.activate(); closeMe() }
  }
  function handleKey(e) {   // true = used (also called by Quick settings, where focus stays in the search field)
    if (e.key === Qt.Key_Down) hot = list.length ? (hot + 1) % list.length : -1
    else if (e.key === Qt.Key_Up) hot = list.length ? (hot - 1 + list.length) % list.length : -1
    else if (e.key === Qt.Key_Right) open(list[hot], true)
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) open(list[hot], e.modifiers & Qt.ShiftModifier)
    else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Left) closeMe()
    else return false
    return true
  }
  Keys.onPressed: e => { if (handleKey(e)) e.accepted = true }

  Text {
    visible: p.list.length === 0
    text: "No tray icons"; color: Theme.dim; font.family: Theme.barFont; font.pixelSize: Theme.barPx
    Layout.margins: 6
  }
  Repeater {
    model: p.list
    MouseArea {
      id: row
      required property var modelData
      required property int index
      Layout.fillWidth: true; implicitHeight: p.rowH
      implicitWidth: line.implicitWidth + 16
      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onContainsMouseChanged: if (containsMouse) p.hot = index
      onClicked: m => p.open(modelData, m.button === Qt.RightButton)
      Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: p.hot === row.index ? Theme.tint : "transparent" }
      Row {
        id: line
        anchors.verticalCenter: parent.verticalCenter; x: 6; spacing: 8
        AppIcon { source: row.modelData.icon; tray: row.modelData; size: Theme.barPx; anchors.verticalCenter: parent.verticalCenter }   // same engine as the bar
        Text { text: row.modelData.tooltipTitle || row.modelData.title || row.modelData.id
               color: Theme.text; font.family: Theme.barFont; font.pixelSize: Theme.barPx; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
}
