// Notes store (markdown). One FOLDER per note in ~/Documents/Notes/<name>/, newest edited first:
//   <name>/<name>.md   the text (plain markdown, "[ ]" / "[x]" lines are checkboxes; idea from AngelOS-Dotfiles, MIT)
//   <name>/images/     its pictures, referenced from the text as ![](images/<file>)
// A note's id is its folder name ("2025-11-07_19-51-32" at first; renamed to the first line when the editor closes). Deleted notes go to Notes/.trash/.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  readonly property string dir: Quickshell.env("HOME") + "/Documents/Notes"
  property var items: []        // [{ id, text }]
  property bool ready: false
  property bool dirty: false    // typed, not yet written
  property var pending: ({})    // ids waiting for the write timer
  property var writers: ({})    // id -> FileView
  signal imageReady(string id, string name)   // a picture was stored in images/: the editor inserts the reference
  signal pasteDone(string id, int code)       // clipboard paste finished: 0 = an image was stored, else the clipboard held none
  function imgDir(id) { return dir + "/" + id + "/images" }
  function imgUrl(id, name) { return "file://" + imgDir(id) + "/" + name }
  function imagesIn(t) { const out = [], re = /!\[[^\]]*\]\(images\/([^)]+)\)/g; let m; while ((m = re.exec(t))) out.push(m[1]); return out }

  function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") }
  function uniqueName(base) { let n = base, i = 2; while (items.some(x => x.id === n)) n = base + "-" + (i++); return n }
  function reload() { if (!dirty && !load.running) load.running = true }
  function get(id) { return items.find(n => n.id === id) }
  function add() {
    const id = uniqueName(stamp()); items = [{ id, text: "" }].concat(items)
    mkdirProc.noteId = id; mkdirProc.command = ["mkdir", "-p", "--", imgDir(id)]; mkdirProc.running = true   // the file is written once the folder exists
    return id
  }
  function setText(id, t) { items = items.map(n => n.id === id ? { id, text: t } : n); dirty = true; pending[id] = true; saveLater.restart() }
  function touch(id) { const n = get(id); if (n) { items = [n].concat(items.filter(x => x.id !== id)); writeNow(id, n.text) } }   // to the top (a rewrite bumps the mtime)
  function remove(id) {
    items = items.filter(n => n.id !== id); delete pending[id]; delete writers[id]
    trash.command = ["sh", "-c", "mkdir -p \"$1/.trash\" && mv -- \"$1/$2\" \"$1/.trash/$2-$(date +%s)\"", "sh", dir, id]; trash.running = true
  }
  function toggleLine(id, line) {   // flip "[ ]" <-> "[x]" on one line
    const n = get(id); if (!n) return;
    const ls = n.text.split("\n"), m = ls[line] && ls[line].match(/^(\s*)\[( |x|X)\](.*)$/); if (!m) return;
    ls[line] = m[1] + "[" + (m[2] === " " ? "x" : " ") + "]" + m[3]; setText(id, ls.join("\n")); flush()
  }
  function writeNow(id, text) {
    if (!writers[id]) writers[id] = fileComp.createObject(root, { path: dir + "/" + id + "/" + id + ".md" })
    writers[id].setText(text)
  }
  function flush() { saveLater.stop(); for (const id in pending) { const n = get(id); if (n) writeNow(id, n.text) } pending = ({}); dirty = false }
  function renameFromTitle(id) {   // an auto-named note takes its first line as the file name (once)
    const n = get(id); if (!n || !/^\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d(-\d+)?$/.test(id) || renameProc.running) return
    const first = (n.text.split("\n").find(l => l.replace(/^[#>*\-\s]*(\[[ xX]\]\s*)?/, "").trim() !== "" && !/^!\[/.test(l.trim())) || "")
    const slug = first.replace(/^[#>*\-\s]*(\[[ xX]\]\s*)?/, "").trim().replace(/[^\p{L}\p{N}_ -]/gu, "").trim().replace(/\s+/g, "-").slice(0, 40).replace(/-+$/, "")
    if (!slug) return
    const nid = uniqueName(slug); if (nid === id) return
    flush(); renameProc.oldId = id; renameProc.newId = nid
    renameProc.command = ["sh", "-c", "mv -n -- \"$1/$2\" \"$1/$3\" && mv -n -- \"$1/$3/$2.md\" \"$1/$3/$3.md\"", "sh", dir, id, nid]; renameProc.running = true
  }
  function pasteImage(id) {   // the clipboard picture -> images/ (wl-paste); exit 3 = none
    if (pasteProc.running) return
    pasteProc.noteId = id; pasteProc.name = id + "-" + Date.now() + ".png"
    pasteProc.command = ["sh", "-c", "mkdir -p \"$1\" && T=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/') && [ -n \"$T\" ] && wl-paste -t \"$T\" > \"$1/$2\" || exit 3", "sh", imgDir(id), pasteProc.name]
    pasteProc.running = true
  }
  function importImage(id, path) {   // a chosen / dropped image file -> images/
    const ext = (path.match(/\.(png|jpe?g|gif|webp|bmp)$/i) || [])[1]; if (!ext || importProc.running) return
    importProc.noteId = id; importProc.name = id + "-" + Date.now() + "." + ext.toLowerCase()
    importProc.command = ["sh", "-c", "mkdir -p \"$1\" && cp -- \"$2\" \"$1/$3\"", "sh", imgDir(id), path, importProc.name]
    importProc.running = true
  }
  function pickImage(id) {   // file chooser (zenity), then importImage
    if (pickProc.running) return
    pickProc.noteId = id
    pickProc.command = ["zenity", "--file-selection", "--title=Add image", "--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp"]
    pickProc.running = true
  }
  function openFolder() { Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && exec xdg-open \"$1\"", "sh", dir]) }

  Component.onCompleted: reload()
  Timer { id: saveLater; interval: 500; onTriggered: root.flush() }
  Component { id: fileComp; FileView { printErrors: false } }
  Process { id: trash }
  Process { id: mkdirProc; property string noteId: ""; onExited: code => { if (code === 0) root.writeNow(noteId, "") } }
  Process { id: renameProc; property string oldId: ""; property string newId: ""
            onExited: code => { if (code === 0) { root.items = root.items.map(n => n.id === oldId ? { id: newId, text: n.text } : n); delete root.writers[oldId] } } }
  Process { id: pasteProc; property string noteId: ""; property string name: ""
            onExited: code => { if (code === 0) root.imageReady(noteId, name); root.pasteDone(noteId, code) } }
  Process { id: importProc; property string noteId: ""; property string name: ""
            onExited: code => { if (code === 0) root.imageReady(noteId, name) } }
  Process {
    id: pickProc; property string noteId: ""
    stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p !== "") root.importImage(pickProc.noteId, p) } }
  }
  Process {
    id: load
    command: ["sh", "-c", "mkdir -p \"$1\"; cd \"$1\" || exit 0; ls -t -- */*.md 2>/dev/null | while IFS= read -r f; do d=${f%%/*}; [ \"$f\" = \"$d/$d.md\" ] && jq -Rs --arg id \"$d\" '{id:$id,text:.}' \"$f\"; done | jq -s .", "sh", root.dir]
    stdout: StdioCollector { onStreamFinished: { try { root.items = JSON.parse(text) } catch (e) { root.items = [] } root.ready = true } }
  }
}
