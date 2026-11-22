// Nothing style: a quiet dot grid over the wallpaper. One static surface per monitor on the Bottom layer (above awww's
// Background layer, under every window), painted once into a Canvas - no per-frame work, no shader, no animation.
// It repaints only when the size or the theme text colour changes. Costs ~45 MB of shell RSS (two full-screen surfaces). Off with `wallpaper_dots = false` in settings.toml.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

Variants {
  model: Prefs.get("wallpaper_dots", true) ? Quickshell.screens : []
  PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "lwts-wallpaper-dots"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}   // clicks pass through

    Canvas {
      id: cv
      anchors.fill: parent
      renderTarget: Canvas.Image   // CPU-painted once, then just a texture
      readonly property color ink: Theme.text
      onInkChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        const ctx = getContext("2d"), step = 18;
        ctx.reset();
        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.13);
        ctx.beginPath();
        for (let y = step / 2; y < height; y += step)
          for (let x = step / 2; x < width; x += step) { ctx.moveTo(x + 1, y); ctx.arc(x, y, 1, 0, 2 * Math.PI) }
        ctx.fill();
      }
    }
  }
}
