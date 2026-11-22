// Video wallpaper only. Stills are drawn by awww-daemon (services/Wallpaper.qml tells it what to show), so a still wallpaper
// costs the shell nothing. This window exists only while a video file is the wallpaper, on the Bottom layer (above awww's
// Background layer), and goes away - freeing the decoder and buffers - when a still is picked again.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

Variants {
  model: Wallpaper.isVideo ? Quickshell.screens : []
  PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "lwts-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.surface

    Loader {
      anchors.fill: parent
      active: Wallpaper.isVideo
      source: Modules.videoUrl
      onLoaded: { item.source = "file://" + Wallpaper.source; item.run = Qt.binding(() => !Wallpaper.paused) }
    }
  }
}
