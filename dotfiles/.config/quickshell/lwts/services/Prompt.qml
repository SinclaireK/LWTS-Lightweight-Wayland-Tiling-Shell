// Yes/No and pick-from-list dialogs for scripts and binds (replaces `rofi -dmenu`). Asking never blocks and returns nothing:
// the command to run is handed over with the question and runs only on Yes / when an item is picked.
//   qs ipc call dialog yesno "Switch to Game Mode?" "game-mode go"
//   qs ipc call dialog pick "Power timer" "Off\n30 min\n1 h" "sleep-timer set {}"     ({} = the picked line)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  Component.onCompleted: console.warn('PROMPT loaded')
  property bool shown: false
  property string title: ""
  property var items: []            // empty = Yes/No
  property string command: ""       // run through sh -c; {} is replaced by the picked item (quoted)
  property int sel: 0

  function yesno(t, cmd) { title = t; items = []; command = cmd; sel = 1; shown = true }
  function pick(t, list, cmd) { title = t; items = list; command = cmd; sel = 0; shown = true }
  function close() { shown = false }
  function accept(i) {
    const item = items.length ? items[i] : "";
    const c = command.replace("{}", "'" + String(item).replace(/'/g, "'\\''") + "'");
    shown = false;
    if (items.length || i === 1) Quickshell.execDetached(["sh", "-c", c]);   // Yes/No: index 1 = Yes
  }

  IpcHandler {
    target: "dialog"
    function yesno(title: string, command: string): void { root.yesno(title, command) }
    function pick(title: string, items: string, command: string): void { root.pick(title, items.split("\n").filter(x => x), command) }
  }
}
