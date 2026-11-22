// The lock's stage on a plain overlay, both ways. Lock request (Lock.pre): the blurred wallpaper fades in over the windows while the plate
// grows out of the bar, while the session lock is already starting underneath (services/Lock.qml). Unlock (Lock.veil): the
// lock's content goes first, the session unlocks at once and this veil (the plate and blur as drawn at the last frame) folds into the bar
// while its blur fades out over the returning windows: the same motion played back. Top layer, click-through.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

Variants {
  model: Quickshell.screens
  PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    visible: Lock.veil || Lock.pre
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "lwts-lockveil"
    anchors { top: true; bottom: true; left: true; right: true }
    implicitWidth: screen.width; implicitHeight: screen.height   // the window is mapped under the lock, where it gets no size of its own: a thin stretched strip otherwise
    mask: Region {}

    readonly property bool main: screen.name === ((Quickshell.screens.find(s => s.name === Prefs.get("primary_monitor", "")) || Quickshell.screens.find(s => s.name === "DP-2" || s.name === "eDP-1") || Quickshell.screens[0]) || ({ name: "" })).name

    Loader {   // fresh on every unlock: starts grown (the lock's last frame), then folds into the bar while the blur melts away
      id: ld
      width: win.screen.width; height: win.screen.height   // not anchors.fill: the window's own size lags
      active: Lock.veil || Lock.pre
      sourceComponent: LockStage {
        id: stg
        veil: true; plain: !win.main; screenName: win.screen.name
        driven: Lock.pre    // a lock overlay follows the shared opening progress; an unlock veil starts grown and folds by itself
        opened: !Lock.pre
        Component.onCompleted: if (Lock.pre && !win.main) afterFrames(1, () => Lock.startOpening())   // the main monitor starts once its content has loaded: the heavy frames of the loading would eat the fade
        hideContent: !Lock.pre
        Loader {   // the clock and the player come up with the plate (the real surface draws the same picture): not after the lock engaged
          anchors.fill: parent
          active: Lock.pre && win.main
          asynchronous: true
          sourceComponent: LockContent { ui: true }
          onLoaded: stg.afterFrames(2, () => Lock.startOpening())
        }
      }
    }

    Timer { id: done; interval: Motion.off ? 0 : Motion.fit(Motion.slow * Lock.anim * (1 + Motion.exitRatio) / 2 + 130); onTriggered: Lock.veil = false }
    Connections {
      target: Lock
      function onWantChanged() { if (!Lock.want && Lock.veil && ld.item) ld.item.afterFrames(3, () => { if (ld.item) ld.item.opened = false; done.restart() }) }   // hold the grown, opaque veil ~8 frames: the returning windows (a browser) draw their heavy first frame under it, then the fold has the GPU to itself
    }
  }
}
