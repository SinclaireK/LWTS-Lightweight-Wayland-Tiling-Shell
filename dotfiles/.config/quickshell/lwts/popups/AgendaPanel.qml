// Day block of the time drop (under the calendar): the picked day's classes / events from the Schedule data widget (DataW, calendar.lua `days`)
// + your own reminders kept in the note "Plans" (Notes module, see services/plans.js: `[ ] 2026-11-25 17:30 text`; a time puts it among the classes)
// + the weather row (today only). Click an item = tick, hover x = remove, the "+" row adds one for the picked day; Services/Reminders.qml fires them.
// The rows are not part of panelkeys (they take no Up/Down focus); the add field takes keys only when clicked / Ctrl+N.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../modules/dataw"
import "../modules/notes"
import "../services/plans.js" as Plans
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: a
  spacing: 2
  readonly property bool notesOk: Modules.enabled("notes")
  readonly property var def: DataW.defs.find(d => d.cmd && d.cmd.join(" ").indexOf("calendar.lua") >= 0)
  readonly property var v: def ? DataW.values[def.id] : null
  property date day: new Date()   // the picked day (the calendar sets it)
  readonly property string dayKey: Qt.formatDate(day, "yyyy-MM-dd")
  readonly property bool isToday: dayKey === Qt.formatDate(clock.date, "yyyy-MM-dd")
  readonly property string dayLabel: isToday ? "Today" : Qt.formatDate(day, "ddd d MMM")
  signal reset()   // back to today
  readonly property var classes: v ? (v.days ? (v.days[dayKey] || []) : (isToday && v.list ? v.list : [])) : []
  readonly property var wx: DataW.values.weather
  readonly property bool hasWx: isToday && !!wx && !!wx.value && wx.value !== "--"
  readonly property string nowHM: Qt.formatTime(clock.date, "HH:mm")
  SystemClock { id: clock; precision: SystemClock.Minutes }

  // ---- own items: the note "Plans" ----
  readonly property var note: notesOk ? Notes.items.find(n => Plans.isPlans(n)) || null : null
  readonly property var allTasks: note ? Plans.parse(note.text) : []
  readonly property var tasks: allTasks.filter(t => t.date === dayKey || (t.date === "" && isToday))   // an undated line counts for today
  readonly property var marks: {   // days with open items: a dot in the calendar
    const m = ({}); for (const t of allTasks) if (t.date !== "" && !t.done) m[t.date] = (m[t.date] || 0) + 1; return m
  }
  // what is shown: classes + timed items by time, then the untimed (open first, ticked last); capped so the column never grows
  readonly property var rows: {
    const timed = classes.map(c => ({ kind: "class", time: c.s, text: c.t + (c.p ? " · " + c.p : ""), on: c.on === true, over: isToday && c.e <= nowHM }))
      .concat(tasks.filter(t => t.time !== "").map(t => ({ kind: "task", time: t.time, text: t.text, line: t.line, done: t.done })))
      .sort((x, y) => x.time < y.time ? -1 : x.time > y.time ? 1 : 0)
    const plain = tasks.filter(t => t.time === "").map(t => ({ kind: "task", time: "", text: t.text, line: t.line, done: t.done }))
      .sort((x, y) => (x.done ? 1 : 0) - (y.done ? 1 : 0))
    return timed.concat(plain)
  }
  readonly property int maxRows: 6
  readonly property bool hasNext: isToday && classes.length === 0 && !!v && !!v.sub
  readonly property bool has: true   // the add row alone is enough to show the block
  signal leave()   // Esc in the add field: the owner takes the keys back
  function focusAdd() { addField.forceActiveFocus() }

  function ensureNote(then) {   // the note "Plans" is created on the first item (the title line names the file)
    if (note) { then(note.id); return }
    const id = Notes.add()
    mk.id = id; mk.then = then; mk.restart()   // Notes.add writes the empty file once its folder exists: wait for that, then fill it
  }
  Timer { id: mk; property string id: ""; property var then: null; interval: 350
          onTriggered: { Notes.setText(id, "Plans\n"); Notes.flush(); Notes.renameFromTitle(id); if (then) then(id) } }
  function addTask(raw) {
    const t = raw.trim(); if (t === "") return
    ensureNote(id => { const n = Notes.get(id); if (!n) return; Notes.setText(id, n.text.replace(/\n*$/, "\n") + "[ ] " + dayKey + " " + t + "\n"); Notes.flush() })
  }
  function removeTask(line) {
    if (!note) return
    const ls = note.text.split("\n"); ls.splice(line, 1); Notes.setText(note.id, ls.join("\n")); Notes.flush()
  }
  Component.onCompleted: if (notesOk) Notes.reload()

  RowLayout {   // the picked day + how many things it holds; "Today" jumps back when another day is picked
    Layout.fillWidth: true; spacing: 10
    UiCaption { text: a.dayLabel; color: Theme.text }
    UiNum { visible: a.rows.length > 0; text: a.rows.length; size: Math.round(14 * Theme.scale); color: Theme.dim }
    Item { Layout.fillWidth: true }
    UiButton { visible: !a.isToday; text: "Today"; flat: true; onClicked: a.reset() }
  }
  UiCaption { visible: a.rows.length === 0 && !a.hasNext; Layout.leftMargin: 8; text: "Nothing planned" }
  Repeater {
    model: a.rows.slice(0, a.maxRows)
    Item {
      id: r
      required property var modelData
      readonly property bool task: modelData.kind === "task"
      Layout.fillWidth: true; Layout.preferredHeight: Math.round(22 * Theme.scale)
      opacity: (task && modelData.done) || modelData.over ? 0.4 : 1
      MouseArea {
        id: rm
        anchors.fill: parent; hoverEnabled: true; enabled: r.task
        cursorShape: r.task ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: Notes.toggleLine(a.note.id, r.modelData.line)
      }
      Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; color: r.task && rm.containsMouse ? Theme.fillHover : "transparent" }
      RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        spacing: 10
        Item {   // the key column: a class = its time; an item = a box (+ its time)
          Layout.preferredWidth: Math.round(60 * Theme.scale); Layout.fillHeight: true
          Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Rectangle {
              visible: r.task; width: 11; height: 11; radius: 2; anchors.verticalCenter: parent.verticalCenter
              color: r.task && r.modelData.done ? Theme.accent : "transparent"; border.width: 1; border.color: r.task && r.modelData.done ? Theme.accent : Theme.edge
            }
            Text { visible: r.modelData.time !== ""; text: r.modelData.time; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter
                   font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale) }
          }
        }
        Text {
          Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText
          text: r.modelData.text; color: Theme.text; font.strikeout: r.task && r.modelData.done
          font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
        }
        Rectangle { visible: r.modelData.on === true; width: 4; height: 4; radius: 2; color: Theme.accent }   // running now
        UiIconButton { visible: r.task && rm.containsMouse; icon: "x"; size: 18; onClicked: a.removeTask(r.modelData.line) }
      }
    }
  }
  UiCaption { visible: a.rows.length > a.maxRows; Layout.leftMargin: 8; text: "+" + (a.rows.length - a.maxRows) + " more · see Notes" }
  UiKvRow { visible: a.hasNext; Layout.fillWidth: true; key: v ? v.sub : ""; value: v ? v.value : ""; enabled: false }
  Item {   // the add row: "+" then the field (Enter adds, Esc leaves)
    visible: a.notesOk
    Layout.fillWidth: true; Layout.preferredHeight: Math.round(24 * Theme.scale)
    Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; color: addField.activeFocus ? Theme.fillHover : addMa.containsMouse ? Theme.fill : "transparent"
                border.width: addField.activeFocus ? 1 : 0; border.color: Theme.edge }
    MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onClicked: addField.forceActiveFocus() }
    Text { id: plus; x: 8; anchors.verticalCenter: parent.verticalCenter; text: "+"; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(12 * Theme.scale) }
    TextInput {
      id: addField
      anchors { left: parent.left; leftMargin: 8 + Math.round(60 * Theme.scale) + 10 - 8 + 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
      clip: true; color: Theme.text; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
      font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
      Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { a.addTask(text); text = "" }
        else if (e.key === Qt.Key_Escape) { text = ""; focus = false; a.leave() }
        else return
        e.accepted = true
      }
      Text { visible: addField.text === "" && !addField.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Add reminder · 17:30 gym"; color: Theme.dim
             font.family: addField.font.family; font.pixelSize: addField.font.pixelSize; font.capitalization: Font.AllUppercase }
    }
  }
  UiDotLine { visible: a.hasWx; Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
  UiKvRow { visible: a.hasWx; Layout.fillWidth: true; Layout.preferredHeight: Math.round(22 * Theme.scale); key: "Weather"; value: a.hasWx ? a.wx.value + (a.wx.sub ? " · " + a.wx.sub : "") : ""; enabled: false }
}
