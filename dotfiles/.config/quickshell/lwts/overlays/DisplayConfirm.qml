// "Keep these display settings?" - a dialog in the middle of the focused monitor after Settings -> Displays changed
// something (Look.displayPending). Keep / Revert; Enter = Keep, Esc = Revert; after 12 s the old engine reverts
// by itself and the dialog goes. Over everything, takes the keyboard while it is up.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services
import qs.widgets

PanelWindow {
  id: dlg
  readonly property bool on: Look.displayPending !== ""
  visible: on
  screen: Quickshell.screens.find(s => s.name === Compositor.focusedOutput) || Quickshell.screens[0]
  exclusionMode: ExclusionMode.Ignore
  implicitWidth: 340; implicitHeight: 118
  color: "transparent"
  WlrLayershell.namespace: "lwts-osd"
  BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null   // glass only behind the plate
  Region { id: blurRgn; item: blurPlate; radius: Theme.radius }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: on ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  property int left: 12
  Timer {
    running: dlg.on; repeat: true; interval: 250; triggeredOnStart: true
    onTriggered: dlg.left = Math.max(0, Math.ceil((Look.displayDeadline - Date.now()) / 1000))
  }
  property int sel: 0   // 0 Keep, 1 Revert
  onOnChanged: if (on) { sel = 0; keys.forceActiveFocus() }

  component Label: Text { color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); verticalAlignment: Text.AlignVCenter }
  component Button: UiButton {   // the shared button; `focusedBtn` (keys) lights it like a pressed one
    property bool focusedBtn: false
    on: focusedBtn
    implicitWidth: 96; implicitHeight: 26
  }

  Rectangle {
    id: blurPlate
    anchors.fill: parent
    radius: Theme.radius
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
    border.width: 1; border.color: Theme.line

    Item {
      id: keys
      focus: true
      Keys.onPressed: e => {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) dlg.sel = 1 - dlg.sel;
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) dlg.sel === 0 ? Look.keepDisplay() : Look.revertDisplay();
        else if (e.key === Qt.Key_Escape) Look.revertDisplay();
        else return;
        e.accepted = true;
      }
    }
    Column {
      anchors { fill: parent; margins: 14 }
      spacing: 6
      Row {
        spacing: 8
        Icon { name: "monitor"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "Keep these display settings?"; font.weight: Font.DemiBold }
      }
      Label { text: "Reverting in " + dlg.left + " s"; color: Theme.dim; font.pixelSize: Math.round(11 * Theme.scale) }
      Item { width: 1; height: 4 }
      Row {
        anchors.right: parent.right
        spacing: 6
        Button { text: "Revert"; focusedBtn: dlg.sel === 1; onClicked: Look.revertDisplay() }
        Button { text: "Keep"; focusedBtn: dlg.sel === 0; onClicked: Look.keepDisplay() }
      }
    }
  }
}
