// Where to open things "under the cursor": `Pointer.locate(cb)` -> cb(x, y) in global logical px.
// niri's IPC has no pointer query: a transparent full-screen overlay is mapped on every monitor for a moment; the
// compositor sends the pointer "enter" with its position to the one under the cursor, then the overlay goes away.
// No answer within `timeout` ms (pointer hidden / compositor silent): the centre of the focused monitor (upper third).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.services

Singleton {
  id: root
  property var waiting: []        // callbacks of the running probe
  property bool probing: false
  property point last: Qt.point(-1, -1)
  readonly property int timeout: 120

  function locate(cb) {
    waiting = waiting.concat([cb]);
    if (!probing) { probing = true; fallback.restart() }
  }
  function answer(x, y) {
    fallback.stop(); probing = false; last = Qt.point(x, y);
    const cbs = waiting; waiting = [];
    for (const cb of cbs) cb(x, y);
  }
  function centre() {
    const o = Compositor.outputs[Compositor.focusedOutput];
    if (o && o.logical) answer(o.logical.x + Math.round(o.logical.width / 2), o.logical.y + Math.round(o.logical.height / 3));
    else answer(-1, -1);
  }
  Timer { id: fallback; interval: root.timeout; onTriggered: root.centre() }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: probe
      required property var modelData
      screen: modelData
      visible: root.probing
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-pointer"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      HoverHandler {
        onPointChanged: if (root.probing && hovered) root.answer(probe.modelData.x + Math.round(point.position.x), probe.modelData.y + Math.round(point.position.y))
      }
    }
  }

  IpcHandler {   // tests: `probe` then `last` a moment later
    target: "pointer"
    function probe(): void { root.locate(() => {}) }
    function last(): string { return root.last.x + "," + root.last.y }
  }
}
