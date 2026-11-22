// Sticky-style notes for the Notes tab of the clipboard panel (Mod+V). Idea from AngelOS-Dotfiles (MIT): plain text,
// "[ ]" / "[x]" lines are checkboxes. One JSON file (~/.local/state/lwts-notes.json), newest edited first, saved 0.5 s after typing stops.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  readonly property string file: Quickshell.env("HOME") + "/.local/state/lwts-notes.json"
  property var items: []   // [{ id, text }]
  property bool ready: false

  function add() { const n = { id: Date.now(), text: "" }; items = [n].concat(items); save(); return n.id }
  function get(id) { return items.find(n => n.id === id) }
  function setText(id, t) { items = items.map(n => n.id === id ? { id, text: t } : n); saveLater.restart() }
  function touch(id) { const n = get(id); if (n) { items = [n].concat(items.filter(x => x.id !== id)); save() } }   // move to the top
  function remove(id) { items = items.filter(n => n.id !== id); save() }
  function toggleLine(id, line) {   // flip "[ ]" <-> "[x]" on one line
    const n = get(id); if (!n) return;
    const ls = n.text.split("\n"); const m = ls[line] && ls[line].match(/^(\s*)\[( |x|X)\](.*)$/); if (!m) return;
    ls[line] = m[1] + "[" + (m[2] === " " ? "x" : " ") + "]" + m[3]; setText(id, ls.join("\n")); saveLater.stop(); save()
  }
  function save() { store.setText(JSON.stringify(items)) }

  Timer { id: saveLater; interval: 500; onTriggered: root.save() }
  FileView {
    id: store
    path: root.file
    printErrors: false
    onLoaded: { try { root.items = JSON.parse(text()) } catch (e) { root.items = [] } root.ready = true }
    onLoadFailed: root.ready = true
  }
}
