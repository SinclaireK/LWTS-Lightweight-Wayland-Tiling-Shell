// Notes inside the time drop (loaded by TimePanel only while the "notes" module is on): a list on the left, the editor of the picked note on the right.
// Data = the module's `Notes` (markdown files in ~/Documents/Notes). The picked note is shown in the editor at once; typing there saves as you type.
// Mouse: click a row = edit, hover x = delete (twice), right click in the editor = Paste / Copy / Cut / Select all.
// Keyboard: type = filter, ↑/↓ pick, Enter edit, Ctrl+N new, Delete (twice) removes, Esc leaves the editor / clears the filter / closes the drop;
// in the editor Ctrl+V pastes (a clipboard picture becomes an ![](images/…) line), Ctrl+Space = tick / make a box on the line.
// A note is bumped to the top and named from its first line only when it was changed AND the user goes to another note or leaves the page
// (renaming changes its id: never while it is open).
import QtQuick
import QtQuick.Layouts
import "../modules/notes"
import qs.core
import qs.widgets

FocusScope {
  id: pane
  signal closeDrop()
  property var editing: 0          // id (file name) of the note in the editor, 0 = none
  property string loaded: ""       // its text when it was opened: unchanged notes are not bumped / renamed
  property bool loading: false     // the editor text is being replaced: not a user edit
  property int sel: 0
  property bool armed: false       // delete asked once
  property string aside: ""        // "" | "images" | "hints": a list laid over the editor (NotesAside.qml)
  function toggleAside(m) { aside = aside === m ? "" : m }
  function imgUrl(n) { return Notes.imgUrl(editing, n) }
  property string hint: ""         // short feedback in the editor header
  readonly property var curImages: { const n = Notes.get(editing); return n ? Notes.imagesIn(n.text) : [] }
  readonly property var list: Notes.items.filter(n => filter.text === "" || n.text.toLowerCase().indexOf(filter.text.toLowerCase()) >= 0)

  function load(id) {   // show a note in the editor (editing is 0 meanwhile: the text swap must not be saved as an edit)
    const n = Notes.get(id)
    editing = 0; loading = true; edit.text = n ? n.text : ""; loading = false
    loaded = edit.text; editing = n ? id : 0; aside = ""
  }
  function park() {   // done with the shown note: an empty one is removed, a changed one goes to the top and is named from its title
    if (!editing) return
    const id = editing, n = Notes.get(id); editing = 0
    if (!n) return
    if (n.text.trim() === "") { Notes.remove(id); return }
    if (n.text !== loaded) { Notes.touch(id); Notes.renameFromTitle(id) }
  }
  function go(id) { if (id === editing) return; park(); const i = list.findIndex(n => n.id === id); sel = i < 0 ? 0 : i; load(id) }
  function followSel() { const n = list[sel]; if (n) go(n.id); else { park(); load(0) } }
  function create() { park(); filter.text = ""; sel = 0; const id = Notes.add(); load(id); Qt.callLater(() => edit.forceActiveFocus()) }
  function open(id) { go(id); Qt.callLater(() => { edit.forceActiveFocus(); edit.cursorPosition = edit.length }) }
  function openSel() { const n = list[sel]; if (n) open(n.id) }
  function leave() { aside = ""; menu.opened = false; filter.forceActiveFocus() }   // the editor gives the keys back to the list; the note stays shown
  function removeAt(i) {
    const n = list[i]; if (!n) return;
    if (n.text.trim() !== "" && !(armed && sel === i)) { sel = i; armed = true; disarm.restart(); return }
    armed = false; if (n.id === editing) { editing = 0; load(0) }
    Notes.remove(n.id); sel = Math.max(0, Math.min(sel, list.length - 1)); Qt.callLater(followSel)
  }
  function move(d) { sel = Math.max(0, Math.min(list.length - 1, sel + d)); lv.positionViewAtIndex(sel, ListView.Contain); followSel() }
  function tickLine() {   // editor: Ctrl+Space flips "[ ]" <-> "[x]" on the cursor's line, or makes the line a box
    const pos = edit.cursorPosition, ls = edit.text.split("\n"), li = edit.text.substring(0, pos).split("\n").length - 1;
    const m = ls[li].match(/^(\s*)\[( |x|X)\](.*)$/);
    ls[li] = m ? m[1] + "[" + (m[2] === " " ? "x" : " ") + "]" + m[3] : "[ ] " + ls[li];
    edit.text = ls.join("\n"); edit.cursorPosition = Math.min(pos + (m ? 0 : 4), edit.length)
  }
  function pasteHere() { Notes.pasteImage(editing) }   // a picture in the clipboard becomes an image line; no picture -> the text is pasted (pasteDone)
  function dropImage(name) {   // detach: the reference line goes, the file stays in images/
    edit.text = edit.text.split("\n").filter(l => l.indexOf("(images/" + name + ")") < 0).join("\n")
  }
  function openFolder() { Notes.openFolder() }
  function say(t) { hint = t; hintTimer.restart() }
  Timer { id: hintTimer; interval: 2500; onTriggered: pane.hint = "" }
  Connections {
    target: Notes
    function onImageReady(id, name) {
      if (id !== pane.editing) return
      const pos = edit.cursorPosition, lead = pos === 0 || edit.text.charAt(pos - 1) === "\n" ? "" : "\n"
      edit.insert(pos, lead + "![](images/" + name + ")\n"); pane.say("Image added")
    }
    function onPasteDone(id, code) { if (id === pane.editing && code !== 0) edit.paste() }
    function onReadyChanged() { if (Notes.ready && !pane.editing) Qt.callLater(pane.followSel) }
  }
  Timer { id: disarm; interval: 2500; onTriggered: pane.armed = false }
  Component.onCompleted: { Notes.reload(); if (Notes.ready) Qt.callLater(followSel) }
  Component.onDestruction: park()

  RowLayout {
    anchors.fill: parent
    spacing: 12

    // ---- list ----
    ColumnLayout {
      Layout.preferredWidth: 230; Layout.fillHeight: true; spacing: 6
      RowLayout {
        Layout.fillWidth: true; spacing: 6
        Item {
          Layout.fillWidth: true; implicitHeight: 24
          TextInput {
            id: filter
            anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; clip: true
            focus: true; color: Theme.text; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
            font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
            onTextChanged: { pane.sel = 0; Qt.callLater(pane.followSel) }
            Keys.onPressed: e => {
              if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) pane.create()
              else if (e.key === Qt.Key_Down) pane.move(1)
              else if (e.key === Qt.Key_Up) pane.move(-1)
              else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pane.openSel()
              else if (e.key === Qt.Key_Delete && text === "") pane.removeAt(pane.sel)
              else if (e.key === Qt.Key_F1) pane.toggleAside("hints")
              else if (e.key === Qt.Key_Escape) { if (pane.aside !== "") pane.aside = ""; else if (text !== "") text = ""; else pane.closeDrop() }
              else return
              e.accepted = true
            }
            Text { visible: filter.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Filter · Ctrl+N new"; color: Theme.dim
                   font.family: filter.font.family; font.pixelSize: filter.font.pixelSize; font.capitalization: Font.AllUppercase }
          }
        }
        UiButton { text: "+"; flat: true; onClicked: pane.create() }
      }
      UiDotLine { Layout.fillWidth: true }
      ListView {
        id: lv
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; spacing: 5; boundsBehavior: Flickable.StopAtBounds; model: pane.list
        add: Transition { ParallelAnimation {
          NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve }
          NumberAnimation { property: "y"; from: -10; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } } }
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
        displaced: Transition { NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } }
        delegate: Rectangle {   // one row: the title, then the second line + "2/5" (ticked / boxes) or the picture count
          id: card
          required property var modelData
          required property int index
          readonly property var ls: modelData.text.split("\n").filter(l => l.trim() !== "" && !/^\s*!\[[^\]]*\]\(images\//.test(l))
          readonly property string title: ls.length > 0 ? ls[0].replace(/^[#>*\-\s]*(\[[ xX]\]\s*)?/, "") : ""
          readonly property string sub: ls.length > 1 ? ls[1].replace(/^[#>*\-\s]*(\[[ xX]\]\s*)?/, "") : ""
          readonly property int boxes: (modelData.text.match(/^\s*\[( |x|X)\]/gm) || []).length
          readonly property int ticked: (modelData.text.match(/^\s*\[(x|X)\]/gm) || []).length
          readonly property int imgs: Notes.imagesIn(modelData.text).length
          readonly property bool armedHere: pane.armed && pane.sel === index
          readonly property bool shown: pane.editing === modelData.id
          width: ListView.view.width; height: Math.round(44 * Theme.scale); radius: Theme.radiusInner
          color: pane.sel === index ? Theme.fillHover : "transparent"
          border.width: 1; border.color: armedHere ? Theme.red : shown ? Theme.text : Theme.edge   // the note in the editor is outlined bright
          MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; onEntered: pane.sel = index; onClicked: pane.open(card.modelData.id) }
          Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 28 }
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: card.title !== "" ? card.title : "Empty note"
                   color: card.title !== "" ? Theme.text : Theme.dim; font.family: Theme.font; font.weight: Font.DemiBold; font.pixelSize: Math.round(13 * Theme.scale) }
            RowLayout {
              width: parent.width; spacing: 6
              Text { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; text: card.sub; color: Theme.dim
                     font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
              UiCaption { visible: card.boxes > 0; text: card.ticked + "/" + card.boxes }
              UiCaption { visible: card.imgs > 0; text: "IMG " + card.imgs }
            }
          }
          UiIconButton {   // delete: appears on hover / pick; the first click arms (red), the second moves the file to Notes/.trash
            visible: cardMa.containsMouse || pane.sel === index
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 3 }
            icon: "x"; size: 22; on: card.armedHere
            onClicked: pane.removeAt(card.index)
          }
        }
        ColumnLayout {
          visible: lv.count === 0; anchors.centerIn: parent; spacing: 6
          UiNum { Layout.alignment: Qt.AlignHCenter; text: "00"; size: Math.round(40 * Theme.scale); opacity: 0.35 }
          UiCaption { Layout.alignment: Qt.AlignHCenter; text: filter.text === "" ? "No notes · Ctrl+N" : "Nothing found" }
        }
      }
    }

    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.line }

    // ---- editor ----
    ColumnLayout {
      Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
      RowLayout {
        Layout.fillWidth: true; spacing: 6
        UiCaption { visible: pane.editing !== 0; text: pane.hint !== "" ? pane.hint : (Notes.dirty ? "Saving…" : "Saved"); color: pane.hint !== "" || !Notes.dirty ? Theme.text : Theme.dim }
        Item { Layout.fillWidth: true }
        UiButton { text: "?"; flat: true; on: pane.aside === "hints"; onClicked: pane.toggleAside("hints") }
        UiButton { visible: pane.curImages.length > 0; text: "Images " + pane.curImages.length; flat: true; on: pane.aside === "images"; onClicked: pane.toggleAside("images") }
        UiButton { visible: pane.editing !== 0; text: "+ Image"; flat: true; onClicked: Notes.pickImage(pane.editing) }   // a file chooser; pasting a picture is Ctrl+V / right click
        UiButton { text: "Folder"; flat: true; onClicked: pane.openFolder() }
      }
      UiDotLine { Layout.fillWidth: true }
      Rectangle {   // the text
        id: box
        Layout.fillWidth: true; Layout.fillHeight: true
        radius: Theme.radiusInner; color: "transparent"; border.width: 1; border.color: edit.activeFocus ? Theme.text : Theme.edge
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; enabled: pane.editing !== 0; onClicked: { edit.forceActiveFocus(); menu.opened = false } }   // a click anywhere in the box puts the cursor in
        TapHandler { acceptedButtons: Qt.RightButton; enabled: pane.editing !== 0; onTapped: pt => { edit.forceActiveFocus(); menu.x = Math.min(pt.position.x, box.width - menu.width - 4); menu.y = Math.min(pt.position.y, box.height - menu.height - 4); menu.opened = true } }
        Flickable {
          id: fl
          anchors { fill: parent; margins: 8 }
          contentHeight: Math.max(edit.implicitHeight, height); clip: true; boundsBehavior: Flickable.StopAtBounds
          TextEdit {
            id: edit
            width: fl.width; height: Math.max(implicitHeight, fl.height)
            enabled: pane.editing !== 0
            wrapMode: TextEdit.Wrap; color: Theme.text; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk; selectByMouse: true
            font.family: Theme.font; font.pixelSize: Math.round(14 * Theme.scale)
            onTextChanged: if (pane.editing && !pane.loading) Notes.setText(pane.editing, text)
            onCursorRectangleChanged: { const r = cursorRectangle; if (r.y < fl.contentY) fl.contentY = r.y; else if (r.y + r.height > fl.contentY + fl.height) fl.contentY = r.y + r.height - fl.height }
            Keys.onPressed: e => {
              if (e.key === Qt.Key_Escape) { if (menu.opened) menu.opened = false; else pane.leave() }
              else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Space) pane.tickLine()
              else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_V) pane.pasteHere()
              else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) pane.create()
              else if (e.key === Qt.Key_F1) pane.toggleAside("hints")
              else if (e.key === Qt.Key_F2 && pane.curImages.length > 0) pane.toggleAside("images")
              else return
              e.accepted = true
            }
            Text { visible: edit.text === "" && pane.editing !== 0; text: "Write here…\n[ ] a task"; color: Theme.dim; font.family: edit.font.family; font.pixelSize: edit.font.pixelSize }
          }
        }
        ColumnLayout {   // nothing picked
          visible: pane.editing === 0; anchors.centerIn: parent; spacing: 6
          UiNum { Layout.alignment: Qt.AlignHCenter; text: "00"; size: Math.round(32 * Theme.scale); opacity: 0.35 }
          UiCaption { Layout.alignment: Qt.AlignHCenter; text: "No note open · Ctrl+N" }
        }
        Rectangle {   // images / key hints laid over the editor
          anchors.fill: parent; visible: pane.aside !== ""; z: 15; radius: Theme.radiusInner; color: Theme.surface
          border.width: 1; border.color: Theme.edge
          NotesAside { anchors { fill: parent; margins: 10 } pane: pane }
        }
      Rectangle {   // right-click menu (Nothing: outlined, mono caps)
        id: menu
        property bool opened: false
        visible: opened; z: 10; width: 150; height: menuCol.implicitHeight + 8
        radius: Theme.radiusInner; color: Theme.surface; border.width: 1; border.color: Theme.edge
        Column {
          id: menuCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
          Repeater {
            model: [["Paste", "paste"], ["Copy", "copy"], ["Cut", "cut"], ["Select all", "all"]]
            Rectangle {
              id: mi
              required property var modelData
              width: menuCol.width; height: 26; radius: Theme.radiusCtl
              color: miMa.containsMouse ? Theme.fillHover : "transparent"
              UiCaption { anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } text: mi.modelData[0]; color: Theme.text }
              MouseArea {
                id: miMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                  menu.opened = false; edit.forceActiveFocus()
                  const a = mi.modelData[1]
                  if (a === "paste") pane.pasteHere(); else if (a === "copy") edit.copy(); else if (a === "cut") edit.cut(); else edit.selectAll()
                }
              }
            }
          }
        }
      }
      }
    }
  }
  DropArea {   // drop image files onto the editor
    anchors.fill: parent; enabled: !!pane.editing
    onDropped: drop => { for (const u of drop.urls) Notes.importImage(pane.editing, decodeURIComponent(String(u).replace(/^file:\/\//, ""))) }
  }
}
