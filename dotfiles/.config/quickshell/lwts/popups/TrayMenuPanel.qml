// Tray app menu as a bar drop (right click on a tray icon): the app's own menu via QsMenuOpener, in the bar's
// font and size - rows, check marks, separators, submenus with "Back". Closes like every drop (click outside,
// Esc, workspace switch). Keys: ↑ ↓, Enter / → run or enter a submenu, ← back, Esc back / close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.widgets

ColumnLayout {
  id: p
  spacing: 0
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  signal done()   // an entry was run (Quick settings closes the launcher)
  property var menu: null          // set by Popups.qml
  property var stack: menu ? [menu] : []
  property int hot: -1
  readonly property var current: stack.length ? stack[stack.length - 1] : null
  readonly property var items: current ? opener.children.values : []
  readonly property bool checks: items.some(e => e && !e.isSeparator && e.buttonType !== QsMenuButtonType.None)
  readonly property int rowH: Math.round(Theme.barPx * 1.2)

  QsMenuOpener { id: opener; menu: p.current }

  function back() { if (stack.length > 1) { stack = stack.slice(0, -1); hot = -1 } else closeMe() }
  function run(e) {
    if (!e || e.isSeparator || !e.enabled) return;
    if (e.hasChildren) { stack = stack.concat([e]); hot = -1 }
    else { e.triggered(); done(); closeMe() }
  }
  function step(d) {   // next enabled row, skipping separators
    for (let i = 1; i <= items.length; i++) {
      const k = ((hot < 0 && d < 0 ? 0 : hot) + d * i + items.length) % items.length;
      if (!items[k].isSeparator && items[k].enabled) { hot = k; return }
    }
  }
  function handleKey(e) {   // true = used
    if (e.key === Qt.Key_Down) step(1)
    else if (e.key === Qt.Key_Up) step(-1)
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Right) run(items[hot])
    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Escape) back()
    else return false
    return true
  }
  Keys.onPressed: e => { if (handleKey(e)) e.accepted = true }

  component MenuRow: MouseArea {
    property bool lit: false
    Layout.fillWidth: true; implicitHeight: p.rowH
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: parent.lit ? Theme.tint : "transparent" }
  }
  component MenuText: Text {
    font.family: Theme.barFont; font.pixelSize: Theme.barPx; color: Theme.text
    anchors.verticalCenter: parent.verticalCenter
  }

  MenuRow {   // back out of a submenu
    visible: p.stack.length > 1
    implicitWidth: backRow.implicitWidth + 12
    lit: containsMouse
    onClicked: p.back()
    Row { id: backRow; anchors.verticalCenter: parent.verticalCenter; x: 6; spacing: 6
      Icon { name: "caret-left"; color: Theme.dim; font.pixelSize: Theme.barPx; anchors.verticalCenter: parent.verticalCenter }
      MenuText { text: "Back"; color: Theme.dim } }
  }
  Repeater {
    model: p.items
    Item {
      id: it
      required property var modelData
      required property int index
      readonly property var e: modelData
      Layout.fillWidth: true
      implicitHeight: e.isSeparator ? 3 : p.rowH
      implicitWidth: e.isSeparator ? 0 : line.implicitWidth + 16 + (e.hasChildren ? 18 : 0)
      Rectangle { visible: it.e.isSeparator; anchors.centerIn: parent; width: parent.width - 8; height: 1; color: Theme.line }
      MenuRow {
        visible: !it.e.isSeparator
        anchors.fill: parent
        enabled: it.e.enabled
        opacity: it.e.enabled ? 1 : 0.4
        lit: p.hot === it.index
        onContainsMouseChanged: if (containsMouse) p.hot = it.index
        onClicked: p.run(it.e)
        Row {
          id: line
          anchors.verticalCenter: parent.verticalCenter; x: 6; spacing: 6
          Icon { visible: p.checks; width: Theme.barPx; anchors.verticalCenter: parent.verticalCenter
                 color: Theme.accent; font.pixelSize: Theme.barPx; fill: true
                 name: it.e.buttonType === QsMenuButtonType.None || it.e.checkState !== Qt.Checked ? ""
                       : it.e.buttonType === QsMenuButtonType.RadioButton ? "circle" : "check" }
          MenuText { text: (it.e.text || "").replace(/&(?!&)/g, "") }
        }
        Icon { visible: it.e.hasChildren; name: "caret-right"; color: Theme.dim; font.pixelSize: Theme.barPx
               anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 6 }
      }
    }
  }
}
