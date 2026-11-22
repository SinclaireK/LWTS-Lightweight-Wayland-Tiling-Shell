// One-line text field for a settings row (type "input"): Enter = apply, Esc / focus lost = back to the old value.
// `validate(text)` returns an error text or "" (error: red frame + message, nothing is applied). `secret` masks the text.
// Keys normally stay in the launcher input; start() moves them here and `done` hands them back (Launcher: query.forceActiveFocus()).
import QtQuick
import qs.core

Item {
  id: f
  property string value: ""          // the applied value shown while not editing
  property string placeholder: ""
  property bool secret: false
  property var validate: null
  property string error: ""
  readonly property bool editing: input.activeFocus
  signal accepted(string text)
  signal done()                      // editing finished either way: give the keys back
  implicitWidth: 220; implicitHeight: 24

  function start() { input.text = f.value; f.error = ""; input.forceActiveFocus(); input.selectAll() }
  function cancel() { f.error = ""; input.text = f.value; f.done() }
  function commit() {
    const err = f.validate ? f.validate(input.text) : "";
    if (err) { f.error = err; return }
    f.error = ""; f.accepted(input.text); f.done()
  }

  Rectangle {
    anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"
    border.width: 1; border.color: f.error ? Theme.red : f.editing ? Theme.accent : Theme.line
  }
  TextInput {
    id: input
    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
    verticalAlignment: TextInput.AlignVCenter
    clip: true
    color: Theme.text; selectionColor: Theme.accent
    font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale)
    echoMode: f.secret ? TextInput.Password : TextInput.Normal
    text: f.value
    onTextChanged: if (f.error) f.error = ""
    onActiveFocusChanged: if (!activeFocus) { if (f.error || text !== f.value) { f.error = ""; text = f.value } }
    Keys.onPressed: e => {
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { f.commit(); e.accepted = true }
      else if (e.key === Qt.Key_Escape) { f.cancel(); e.accepted = true }
      else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) e.accepted = true
    }
    Text {
      visible: !input.text && !f.editing
      anchors.verticalCenter: parent.verticalCenter
      text: f.secret && f.value ? "••••••••" : f.placeholder
      color: Theme.dim; font: input.font
    }
  }
  Text {   // the validator's message under the field
    visible: !!f.error
    anchors { top: parent.bottom; right: parent.right; topMargin: 1 }
    text: f.error; color: Theme.red
    font.family: Theme.font; font.pixelSize: Math.round(10 * Theme.scale)
  }
}
