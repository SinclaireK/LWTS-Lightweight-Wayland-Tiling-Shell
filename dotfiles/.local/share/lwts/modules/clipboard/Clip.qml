// Clipboard history (replaces cliphist). `wl-paste --watch` runs scripts/clip-event.lua on every copy; the answer is one JSON
// line. Kept: the last 100 texts and 10 images, newest first, duplicates move to the top; saved to ~/.local/state/lwts-clip.json
// so a restart of the shell loses nothing. Starred entries (idea from AngelOS-Dotfiles, MIT) are never dropped or cleared. Copies made while the shell is not running are not recorded.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  readonly property string file: Quickshell.env("HOME") + "/.local/state/lwts-clip.json"
  property var items: []            // [{ t: "text", s } | { t: "image", f }], newest first
  readonly property int maxText: 100
  readonly property int maxImage: 10
  property bool ready: false

  function _same(a, b) { return a.t === b.t && (a.t === "text" ? a.s === b.s : a.f === b.f) }
  readonly property int favCount: items.filter(x => x.fav).length
  function add(it) {
    const old = items.find(x => _same(x, it));
    if (old && old.fav) it.fav = true;   // a starred entry stays starred when copied again
    let list = items.filter(x => !_same(x, it));
    list.unshift(it);
    const keep = [];
    let nt = 0, ni = 0;
    for (const x of list) {
      if (x.fav || (x.t === "text" ? nt++ < maxText : ni++ < maxImage)) keep.push(x);   // favourites never fall off the end
      else if (x.t === "image") Quickshell.execDetached(["rm", "-f", x.f]);
    }
    items = keep; save();
  }
  function remove(i) { const x = items[i]; if (!x) return; if (x.t === "image") Quickshell.execDetached(["rm", "-f", x.f]); items = items.filter((_, k) => k !== i); save() }
  function toggleFav(i) { if (!items[i]) return; items = items.map((x, k) => k === i ? Object.assign({}, x, { fav: !x.fav }) : x); save() }
  function clear(all) {   // keeps favourites unless all
    for (const x of items) if (x.t === "image" && (all || !x.fav)) Quickshell.execDetached(["rm", "-f", x.f]);
    items = all ? [] : items.filter(x => x.fav); save()
  }
  function copy(i) {   // put it back on the clipboard (it becomes the newest entry through the watcher)
    const x = items[i]; if (!x) return;
    if (x.t === "text") Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", x.s]);
    else Quickshell.execDetached(["sh", "-c", "wl-copy --type \"$(file -b --mime-type \"$1\")\" < \"$1\"", "sh", x.f]);
  }
  function save() { store.setText(JSON.stringify(items)) }

  FileView {
    id: store
    path: root.file
    printErrors: false
    onLoaded: { try { root.items = JSON.parse(text()) } catch (e) { root.items = [] } root.ready = true }
    onLoadFailed: root.ready = true
  }
  Process {
    id: watch
    running: true
    command: ["wl-paste", "--watch", "luajit", Qt.resolvedUrl("clip-event.lua").toString().replace("file://", "")]
    stdout: SplitParser {
      onRead: line => {
        let it = null;
        try { it = JSON.parse(line) } catch (e) { return }
        if (it && it.t) root.add(it);
      }
    }
    onExited: restart.start()
  }
  Timer { id: restart; interval: 2000; onTriggered: watch.running = true }
}
