// One stick for GamepadView: rim, deadzone rings, hand (hollow) and game (solid) dots. `view` = the GamepadView.
import QtQuick
import qs.core
import qs.services
import qs.widgets

Item {
  property var view: null           // the GamepadView: inline components cannot see the file's ids
  id: sd
  property int stick: 0                  // 0 left, 1 right
  property real d: 100
  property bool rings: true
  readonly property string side: stick ? "r" : "l"
  readonly property var inXY: view.stickIn(stick)
  readonly property var outXY: PadCal.stickOut(view.t, side, inXY)
  width: d; height: d
  Rectangle { readonly property real rr: 1; width: sd.d * rr; height: width; radius: width / 2; anchors.centerIn: parent
               color: "transparent"; border.width: 1; border.color: Theme.edge }
  Rectangle { readonly property real rr: 1 - view.t[sd.side + "out"] / 100; width: sd.d * rr; height: width; radius: width / 2; anchors.centerIn: parent
               color: "transparent"; border.width: 1; border.color: Theme.line; visible: sd.rings && view.t[sd.side + "out"] > 0 }
  Rectangle { readonly property real rr: Math.max(0.02, view.t[sd.side + "dz"] / 100); width: sd.d * rr; height: width; radius: width / 2; anchors.centerIn: parent
               color: "transparent"; border.width: 1; border.color: Theme.dim; visible: sd.rings && view.t[sd.side + "dz"] > 0 }
  UiDotLine { width: sd.d; anchors.verticalCenter: parent.verticalCenter }
  UiDotLine { width: sd.d; anchors.centerIn: parent; rotation: 90 }
  Rectangle {
    readonly property real s: Math.max(8, sd.d * 0.075)
    width: s; height: s; radius: s / 2; color: "transparent"; border.width: 1.5; border.color: Theme.dim
    x: sd.d / 2 + PadCal.clamp(sd.inXY[0], -1, 1) * sd.d / 2 - s / 2; y: sd.d / 2 + PadCal.clamp(sd.inXY[1], -1, 1) * sd.d / 2 - s / 2
  }
  Rectangle {
    readonly property real s: Math.max(6, sd.d * 0.05) + (view.held(sd.stick ? 318 : 317) ? 4 : 0)   // bigger while the stick is clicked
    width: s; height: s; radius: s / 2; color: Theme.accent
    x: sd.d / 2 + sd.outXY[0] * sd.d / 2 - s / 2; y: sd.d / 2 + sd.outXY[1] * sd.d / 2 - s / 2
  }
}
