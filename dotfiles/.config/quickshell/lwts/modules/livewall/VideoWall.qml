// Live wallpapers module: video wallpaper, loaded only while the wallpaper is a video file (Loader in WallpaperLayer, Modules.videoUrl): no multimedia code is touched
// for still images. Looping, muted, and stopped (not just hidden) while the desktop is not looked at.
import QtQuick
import QtMultimedia

Item {
  id: root
  required property url source
  required property bool run
  MediaPlayer {
    id: player
    source: root.source
    loops: MediaPlayer.Infinite
    videoOutput: out
    audioOutput: AudioOutput { muted: true; volume: 0 }
    Component.onCompleted: if (root.run) play()
  }
  Connections { target: root; function onRunChanged() { if (root.run) player.play(); else player.pause() } }
  VideoOutput { id: out; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
}
