// Directional motion blur as a layer effect: `layer.effect: DirBlur { velX; velY; sizeW; sizeH }` (px moved per frame by the moving
// edges, and the layer's size). The smear is as long as the edge moved this frame, along its direction (shaders/dirblur.frag, built with qsb).
import QtQuick
import qs.core

ShaderEffect {
  property real velX: 0
  property real velY: 0
  property real sizeW: 1
  property real sizeH: 1
  property real gain: 1.0   // 1 = the smear is as long as the edge moved; lower = softer
  readonly property real k: gain * Motion.slowmo   // slowmo (the test knob) makes every frame's step smaller: the smear is kept as at real speed
  property vector2d amount: Qt.vector2d(Math.min(0.5, velX * k / Math.max(1, sizeW)), Math.min(0.5, velY * k / Math.max(1, sizeH)))
  fragmentShader: Qt.resolvedUrl("../shaders/dirblur.frag.qsb")
}
