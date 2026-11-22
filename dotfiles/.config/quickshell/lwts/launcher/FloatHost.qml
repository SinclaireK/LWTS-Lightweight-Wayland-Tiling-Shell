// The launcher's host on a monitor without the bar: a full-screen overlay, input only on the plate.
// Same face as the bar for Launcher.qml (screen, margins, barH, hostOpen, grab, holdKeys, launcherDrop);
// `floating` + `cy` make the drop a plate centred on the cursor.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

PanelWindow {
  id: host
  readonly property bool floating: true
  property real cy: 0                   // plate centre, local px
  readonly property int barH: 0
  readonly property var margins: ({ left: 0 })
  property bool hostOpen: false
  property bool grab: false
  property bool holdKeys: false
  property bool catchClicks: false      // over a fullscreen window: the whole surface takes input, a click outside the plate = clickedAway
  signal clickedAway()
  property Item launcherDrop: null
  property bool clockFlying: false      // same face as the bar: unused here (no bar clock to fly from)
  readonly property Item clockItem: null
  readonly property int unread: Notifs.unread
  visible: hostOpen
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "waybar"
  BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null   // a plate here: all corners round
  Region { id: blurRgn; item: host.launcherDrop ? host.launcherDrop.body : null; radius: host.launcherDrop ? host.launcherDrop.r : 0 }
  WlrLayershell.keyboardFocus: grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None   // see Bar.qml: OnDemand needs a click on niri
  mask: Region { item: host.launcherDrop; Region { item: host.catchClicks ? catcher : null } }
  MouseArea { id: catcher; anchors.fill: parent; z: -1; acceptedButtons: Qt.AllButtons; onPressed: host.clickedAway() }
}
