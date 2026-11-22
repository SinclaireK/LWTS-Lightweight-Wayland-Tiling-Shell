// A plate that grows out of the bar like a drop: its top flows into the bar through two concave fillets
// (radius = `rounding`; 0 = a straight T joint), the bottom corners are rounded.
// One macOS-like spring (small single overshoot) drives width and height together; open() / close() -> closed().
// Built from plain Rectangles + two static fillet Shapes, so a frame costs only a resize: smooth at 144 Hz.
// Content is clipped to the body and fades in. flip: the bar is at the bottom, the drop grows upwards.
import QtQuick
import QtQuick.Shapes
import qs.core

Item {
  id: drop
  default property alias content: inner.data
  property real fullWidth: 400
  property real contentWidth: fullWidth   // the target width when fullWidth itself is animated: the content never reflows per frame
  // a new content width while open (quick settings <-> settings): the new content fades up instead of reflowing
  property real swapIn: 1
  onContentWidthChanged: if (settled) swapFade.restart()
  NumberAnimation { id: swapFade; target: drop; property: "swapIn"; from: 0; to: 1; duration: Motion.off ? 0 : 340 }   // linear driver, eased below
  property real fullHeight: 200
  property bool flip: false
  property bool plate: false         // no bar to flow from: a plain rounded plate (launcher on another monitor)
  property real p: 0                 // spring 0..1 (overshoots a little)
  readonly property bool opened: p > 0
  readonly property bool settled: !openAnim.running && !closeAnim.running && p > 0
  signal closed()

  readonly property real f: Theme.radius          // fillet radius = rounding (was 2x: the joint looked too round)
  // Placement: centred under anchorX (host px; -1 = host centre). The drop sits flush with an end of the bar
  // (its side continues the bar's side straight down) only when it would not fit there otherwise, or the gap
  // left to that end would be narrower than a fillet. A drop too wide for both stays centred in the host.
  property real anchorX: -1
  property real hostWidth: parent ? parent.width : 0
  readonly property real cx: anchorX < 0 ? hostWidth / 2 : anchorX
  readonly property bool wide: fullWidth + 4 * f > hostWidth
  readonly property bool flushLeft: !wide && cx - fullWidth / 2 < 2 * f
  readonly property bool flushRight: !wide && cx + fullWidth / 2 > hostWidth - 2 * f
  x: wide ? Math.round((hostWidth - width) / 2) : flushLeft ? 0 : flushRight ? hostWidth - width : Math.round(cx - width / 2)
  readonly property real fl: flushLeft || plate ? 0 : f
  readonly property real fr: flushRight || plate ? 0 : f
  readonly property real r: Theme.radius          // bottom corners
  readonly property real w: fullWidth * (0.6 + 0.4 * p)
  readonly property real h: Math.max(0, fullHeight * p)
  // glass: the bar's blur region takes the body (not the fillets) with these corners
  readonly property Item body: bodyBox
  readonly property real rTop: plate || flip ? r : 0
  readonly property real rBottom: plate || !flip ? r : 0
  readonly property color fill: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)

  readonly property var springCurve: Motion.dropCurve   // spring (Motion), also for size changes by the user
  function open() { closeAnim.stop(); openAnim.restart() }
  function close() { if (!opened || closeAnim.running) return; openAnim.stop(); closeAnim.restart() }
  NumberAnimation { id: openAnim; target: drop; property: "p"; to: 1; duration: Motion.dropOpen
                    easing.type: Easing.BezierSpline; easing.bezierCurve: drop.springCurve }
  NumberAnimation { id: closeAnim; target: drop; property: "p"; to: 0; duration: Motion.dropClose
                    easing.type: Easing.InQuad; onFinished: drop.closed() }

  width: w + fl + fr
  height: h
  visible: opened

  component Fillet: Item {   // concave corner between the bar edge and the drop side; static shape, clipped by height
    width: drop.f; height: Math.min(drop.f, drop.h)
    clip: true
    Shape {
      width: drop.f; height: drop.f
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeWidth: -1; fillColor: drop.fill
        startX: 0; startY: 0
        PathArc { x: drop.f; y: drop.f; radiusX: drop.f; radiusY: drop.f }
        PathLine { x: drop.f; y: 0 }
      }
      ShapePath {
        strokeWidth: 1; strokeColor: Theme.line; fillColor: "transparent"
        startX: 0; startY: 0.5
        PathArc { x: drop.f - 0.5; y: drop.f; radiusX: drop.f - 0.5; radiusY: drop.f - 0.5 }
      }
    }
  }

  Rectangle { visible: drop.plate; anchors.fill: parent; radius: drop.r; color: drop.fill; border.width: 1; border.color: Theme.line }

  property real contentIn: (!closeAnim.running && drop.p > 0.35) ? 1 : 0   // the content fades in once the plate is mostly out
  Behavior on contentIn { NumberAnimation { duration: Motion.fit(Motion.normal); easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
  readonly property real fxPad: 28   // room outside the drop (away from the bar, and to the sides)
  Item {   // the plate only (the content does not move, it fades)
    id: fx
    x: -drop.fxPad; y: drop.flip ? -drop.fxPad : 0
    width: drop.width + 2 * drop.fxPad; height: drop.height + drop.fxPad
    Item {
      x: drop.fxPad; y: drop.flip ? drop.fxPad : 0
      width: drop.width; height: drop.height
  Item {   // visuals (mirrored for a bottom bar)
    anchors.fill: parent
    visible: !drop.plate
    transform: Scale { yScale: drop.flip ? -1 : 1; origin.y: drop.height / 2 }
    Fillet { x: 0; visible: !drop.flushLeft }
    Fillet { x: drop.fl + drop.w; visible: !drop.flushRight; transform: Scale { xScale: -1; origin.x: drop.f / 2 } }
    Item {   // body fill: square top (hidden above the clip), rounded bottom
      x: drop.fl; width: drop.w; height: drop.h
      clip: true
      Rectangle { y: -drop.r; width: parent.width; height: drop.h + drop.r; radius: drop.r; color: drop.fill }
    }
    Item {   // body frame: bottom with its corners; nothing along the bar
      x: drop.fl; y: Math.max(0, drop.h - drop.r - 1); width: drop.w; height: drop.h - y
      clip: true
      Rectangle {
        y: -parent.y - drop.r; width: parent.width; height: drop.h + drop.r
        radius: drop.r
        color: "transparent"
        border.width: 1; border.color: Theme.line
      }
    }
    // sides: from under a fillet, or from the bar itself on a flush side
    Rectangle { x: drop.fl; y: drop.flushLeft ? 0 : Math.min(drop.f, drop.h); width: 1; color: Theme.line
                height: Math.max(0, drop.h - drop.r - 1 - y) }
    Rectangle { x: drop.fl + drop.w - 1; y: drop.flushRight ? 0 : Math.min(drop.f, drop.h); width: 1; color: Theme.line
                height: Math.max(0, drop.h - drop.r - 1 - y) }
  }

    }
  }

  Item {   // visible body: the content never shows over the fillets
    id: bodyBox
    x: drop.fl; width: drop.w; height: drop.h
    clip: true
    Item {   // content area, fixed full size so the layout does not reflow while growing
      x: (drop.w - drop.contentWidth) / 2
      y: drop.flip ? drop.h - drop.fullHeight : 0
      width: drop.contentWidth; height: drop.fullHeight
      // opening: fades in over the second half; closing: stays and slides into the bar with the body (no empty plate)
      // (the open fade has its own clock: the spring brings the plate to ~90% in a sixth of the time, a fade tied to it lasted three frames)
      opacity: closeAnim.running ? Math.min(1, drop.p / 0.25) : drop.contentIn
      Item {
        id: inner
        anchors.fill: parent
        opacity: Math.min(1, drop.swapIn / 0.6)
        transform: Translate { y: Math.round(14 * Math.pow(1 - drop.swapIn, 3)) }
      }
    }
  }
}
