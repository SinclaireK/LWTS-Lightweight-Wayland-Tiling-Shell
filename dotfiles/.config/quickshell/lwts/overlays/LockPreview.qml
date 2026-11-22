// A window with the lock screen's look (same backdrop + LockContent), to tune it live. No session lock, no PAM: Enter only clears the field.
// Open: `qs -c lwts ipc call lockpreview toggle`. It reads the lock_* prefs live, so Settings -> Lock screen changes show at once.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
  id: root
  property bool shown: false
  property bool grown: false
  property string shotFile: ""
  Timer { id: grow; interval: 400; onTriggered: root.grown = true }
  function replay() { grown = false; grow.restart() }
  onShownChanged: if (shown) replay()
  IpcHandler {
    target: "lockpreview"
    function toggle(): void { root.shown = !root.shown }
    function replay(): void { root.replay() }   // fold into the bar and grow again
    function shot(path: string): void { root.shotFile = path === "" ? "" : "file://" + path }
  }
  LazyLoader {
    active: root.shown
    FloatingWindow {
      visible: true
      implicitWidth: 1280; implicitHeight: 720   // half of a 2560x1440 screen
      title: "Lock preview"
      color: Theme.surface
      onVisibleChanged: if (!visible) root.shown = false
      Item {   // a full-size screen drawn at half scale, so sizes read like the real lock
        readonly property var scr: Quickshell.screens.reduce((a, b) => !a || b.width > a.width ? b : a, null)   // the widest one: the main monitor
        width: scr ? scr.width : 2560; height: scr ? scr.height : 1440
        scale: Math.min(parent.width / width, parent.height / height); transformOrigin: Item.TopLeft
        LockStage {
          anchors.fill: parent; opened: root.grown
          shot: root.shotFile   // set by `ipc call lockpreview shot <path>` to try the first-frame screenshot
          LockContent { anchors.fill: parent; onSubmit: pw => {} }
        }
      }
    }
  }
}
