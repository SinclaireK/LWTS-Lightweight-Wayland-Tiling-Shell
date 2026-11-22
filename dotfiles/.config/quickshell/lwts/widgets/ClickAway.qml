// "Click anywhere else closes it" for niri (HyprlandFocusGrab has no counterpart). Two ways to leave:
//  - another window takes focus (clicked, alt-tabbed): Compositor.focusedWindowId changes to a real window id;
//    focus moving to this shell's own layer surface gives -1 and is ignored, so opening a pop-up does not close it;
//  - a click on the empty desktop: a transparent plate on the Bottom layer (below windows, above the wallpaper).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

Scope {
  id: root
  property var windows: []     // unused here; kept so call sites read like the Hyprland grab they replace
  property bool active: false
  signal cleared()

  Connections {
    target: Compositor
    enabled: root.active
    function onFocusedWindowIdChanged() { if (Compositor.focusedWindowId >= 0) root.cleared() }
  }
  Variants {
    model: root.active ? Quickshell.screens : []
    PanelWindow {
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "lwts-clickaway"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.cleared() }
    }
  }
}
