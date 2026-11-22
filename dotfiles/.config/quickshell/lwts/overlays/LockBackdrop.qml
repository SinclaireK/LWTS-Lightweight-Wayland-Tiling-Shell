// The lock screen's background: the blurred wallpaper (the plate's translucent fill is drawn by LockStage.qml).
import QtQuick
import QtQuick.Effects
import qs.core
import qs.services

Item {
  property string screenName: ""
  readonly property string pre: Lock.blurUrl(screenName)   // the cached, already blurred picture (services/Lock.qml); "" = blur live (fallback)
  // follows Settings -> Look -> Materials: Solid = the wallpaper without blur, otherwise the Blur level
  readonly property string lvl: Lock.blurLvl
  layer.enabled: pre === ""   // the blur is rendered once into a texture; the growth then only composites it (60 Hz: no shader pass per frame)
  Image { anchors.fill: parent; visible: pre !== ""; source: pre; fillMode: Image.PreserveAspectCrop; cache: true }
  Image {   // live fallback: wallpaper at the surface's pixel size, blurred and dimmed
    id: bg
    anchors.fill: parent
    source: pre === "" ? Lock.wallUrl : ""
    sourceSize: Qt.size(parent.width / Lock.blurShrink, parent.height / Lock.blurShrink)
    fillMode: Image.PreserveAspectCrop
    cache: true
    visible: false
  }
  MultiEffect {
    anchors.fill: parent; source: bg; visible: pre === "" && bg.status === Image.Ready; brightness: -0.06; saturation: -0.15; contrast: -0.08
    blurEnabled: lvl !== "off"; blur: lvl === "light" ? 0.5 : 1.0; blurMax: lvl === "strong" ? 64 : lvl === "light" ? 24 : 48
  }
}
