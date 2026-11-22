// "Notes" tab of the clipboard panel: cards with clickable "[ ]" checkboxes; Enter or a click on the text opens the editor,
// Esc leaves it. Ctrl+N new note, Delete (twice) removes the selected one. The panel's search field filters by text.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services

Item {
  id: tab
  property string query: ""
  property int sel: 0
  property int editing: 0        // id of the note in the editor, 0 = list
  property bool armed: false     // Delete pressed once
  readonly property var list: Notes.items.filter(n => query === "" || n.text.toLowerCase().indexOf(query.toLowerCase()) >= 0)
  signal leave()                 // editor closed: give the focus back to the panel's search field

  function create() { editing = Notes.add(); sel = 0; edit.text = ""; Qt.callLater(() => edit.forceActiveFocus()) }
  function openSel() { const n = list[sel]; if (n) open(n.id) }
  function open(id) { editing = id; edit.text = Notes.get(id).text; edit.forceActiveFocus(); edit.cursorPosition = edit.length }
  function close() { if (editing) { const n = Notes.get(editing); if (n && n.text.trim() === "") Notes.remove(editing); else Notes.touch(editing) } editing = 0; sel = 0; tab.leave() }
  function removeSel() {
    const n = list[sel]; if (!n) return;
    if (n.text.trim() !== "" && !armed) { armed = true; disarm.restart(); return }
    armed = false; Notes.remove(n.id); sel = Math.max(0, Math.min(sel, list.length - 2))
  }
  function move(d) { sel = Math.max(0, Math.min(list.length - 1, sel + d)) }
  Timer { id: disarm; interval: 2500; onTriggered: tab.armed = false }

  ListView {
    anchors.fill: parent; visible: tab.editing === 0
    clip: true; spacing: 6; model: tab.list
    delegate: Rectangle {
      id: card
      required property var modelData
      required property int index
      readonly property var lines: modelData.text.split("\n").slice(0, 7)
      width: ListView.view.width; height: Math.min(150, body.implicitHeight + 16); radius: Theme.radiusInner
      color: tab.sel === index ? Theme.tint : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL1)
      border.width: 1; border.color: tab.armed && tab.sel === index ? Theme.red : Theme.line
      MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: tab.sel = index; onClicked: tab.open(card.modelData.id) }
      Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 2
        Repeater {
          model: card.lines
          Item {
            required property string modelData
            required property int index
            readonly property var m: modelData.match(/^\s*\[( |x|X)\]\s?(.*)$/)
            width: body.width; height: 18
            Text {
              visible: parent.m !== null; x: 0; width: 20; height: parent.height; verticalAlignment: Text.AlignVCenter
              text: parent.m && parent.m[1] !== " " ? "☑" : "☐"; color: parent.m && parent.m[1] !== " " ? Theme.accent : Theme.dim
              font.pixelSize: 15 * Theme.scale
              MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: Notes.toggleLine(card.modelData.id, parent.parent.index) }
            }
            Text {
              x: parent.m ? 22 : 0; width: parent.width - x; height: parent.height; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
              text: parent.m ? parent.m[2] : modelData; textFormat: Text.PlainText
              font.family: Theme.font; font.pixelSize: 13 * Theme.scale
              font.weight: index === 0 && !parent.m ? Font.DemiBold : Font.Normal
              color: parent.m && parent.m[1] !== " " ? Theme.dim : Theme.text
              font.strikeout: parent.m !== null && parent.m[1] !== " "
            }
          }
        }
        Text { visible: card.modelData.text.trim() === ""; text: "Empty note"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.scale }
      }
    }
    Text {
      visible: parent.count === 0; anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter
      text: Notes.ready ? "No notes yet · Ctrl+N\n[ ] a line like this becomes a checkbox" : "…"
      color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.scale
    }
  }

  Rectangle {
    anchors.fill: parent; visible: tab.editing !== 0
    radius: Theme.radiusInner
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL1)
    border.width: 1; border.color: Theme.accent
    TextEdit {
      id: edit
      anchors { fill: parent; margins: 8 }
      wrapMode: TextEdit.Wrap; color: Theme.text; selectionColor: Theme.accent
      font.family: Theme.font; font.pixelSize: 14 * Theme.scale
      onTextChanged: if (tab.editing) Notes.setText(tab.editing, text)
      Keys.onEscapePressed: tab.close()
      Text { visible: edit.text === ""; text: "Title\n[ ] a task"; color: Theme.dim; font: edit.font }
    }
  }
}
