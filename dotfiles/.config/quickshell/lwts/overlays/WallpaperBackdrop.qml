// Overview backdrop: niri draws a surface with place-within-backdrop only behind the workspaces. A static "chaotic" gradient:
// four soft radial blobs in theme colours, placed from a hash of the wallpaper path (same wallpaper = same picture). No image
// decode, no blur pass, nothing redraws after the first frame.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

Variants {
  model: Prefs.get("backdrop_style", "gradient") === "off" ? [] : Quickshell.screens   // off: niri's own plain backdrop
  PanelWindow {
    id: bw
    required property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "lwts-wallpaper-blur"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.surface

    function hash(t) { let h = 7; for (let i = 0; i < t.length; i++) h = (h * 31 + t.charCodeAt(i)) % 1000003; return h }
    readonly property int seed: hash(Wallpaper.original)
    function rnd(i) { return ((Math.sin(seed * 12.9898 + i * 78.233) * 43758.5453) % 1 + 1) % 1 }
    readonly property var cols: [Theme.accent, Theme.c("tertiary", "#d3869b"), Theme.c("secondary", "#89b482"), Theme.c("primary_container", "#504945")]

    readonly property bool dark: Session.dark

    Repeater {
      model: 4
      Shape {
        required property int index
        readonly property real r: Math.max(bw.width, bw.height) * (0.45 + bw.rnd(index * 4 + 2) * 0.3)
        x: bw.rnd(index * 4) * bw.width - r
        y: bw.rnd(index * 4 + 1) * bw.height - r
        width: r * 2; height: r * 2
        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: r; centerY: r; centerRadius: r; focalX: r; focalY: r
            GradientStop { position: 0; color: Qt.alpha(bw.cols[index], 0.34) }
            GradientStop { position: 1; color: Qt.alpha(bw.cols[index], 0) }
          }
          PathRectangle { x: 0; y: 0; width: r * 2; height: r * 2 }
        }
      }
    }
    // dark themes: pull the whole backdrop down a little so the windows stand out
    Rectangle { anchors.fill: parent; color: "black"; opacity: bw.dark ? 0.3 : 0 }
  }
}
