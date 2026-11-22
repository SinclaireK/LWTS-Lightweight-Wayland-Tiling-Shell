// OSD like Plasma 6: a plate at the bottom centre of the focused monitor - glass, it sits over
// the content. Same content as the drop (widgets/OsdContent.qml), state in services/OsdState.qml.
// Fades and rises a little in, clicks pass through. Stays in while a bar drop is out (it shows the value already).
// One window per screen: a layer surface does not move cleanly when `screen` changes. Hidden = no surface.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services
import qs.widgets

Scope {
  id: root
  required property var bar
  property string target: ""   // monitor name, taken at each change so the plate does not jump while it is out
  readonly property bool want: OsdState.shown && !bar.dropItem
  Connections { target: OsdState; function onPopped() { root.target = Compositor.focusedOutput !== "" ? Compositor.focusedOutput : root.bar.screen.name } }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: osd
      required property var modelData
      screen: modelData
      readonly property bool on: root.want && root.target === modelData.name
      property real k: on ? 1 : 0   // 0 hidden .. 1 out
      Behavior on k { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
      visible: on || k > 0

      anchors.bottom: true
      margins.bottom: Math.round(modelData.height * 0.08)
      exclusionMode: ExclusionMode.Ignore
      implicitWidth: 360   // fixed: resizing a layer surface flickers, the plate inside follows the content
      implicitHeight: Prefs.barHeight + 8
      color: "transparent"
      mask: Region {}
      WlrLayershell.namespace: "lwts-osd"
      BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null   // glass only behind the plate
      Region { id: blurRgn; item: blurPlate; radius: Theme.radius }
      WlrLayershell.layer: WlrLayer.Overlay

      Rectangle {   // the size and fill of a drop: one look for one role
        id: blurPlate
        anchors.horizontalCenter: parent.horizontalCenter
        width: content.implicitWidth + 24; height: parent.height
        Behavior on width { NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
        opacity: osd.k
        transform: Translate { y: (1 - osd.k) * 8 }
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
        border.width: 1; border.color: Theme.line
        OsdContent { id: content; anchors.centerIn: parent }
      }
    }
  }
}
