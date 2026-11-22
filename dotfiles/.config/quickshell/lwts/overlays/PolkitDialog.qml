// Polkit agent: the "enter your password" dialog for pkexec / GUI apps that need root. Registers on the session bus
// (replaces hyprpolkitagent / polkit-kde-agent). While the shell is not running there is no agent, so nothing can ask.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.core
import qs.services

Scope {
  id: root
  PolkitAgent { id: agent }
  readonly property var flow: agent.flow
  readonly property bool open: agent.isActive && !!flow && !flow.isCompleted

  Variants {
    model: root.open ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-polkit"
      BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null   // glass only behind the plate
      Region { id: blurRgn; item: blurPlate; radius: Theme.radius }
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.35)

      Rectangle {
        id: blurPlate
        anchors.centerIn: parent
        width: 380; height: col.implicitHeight + 32
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.max(Theme.opacityL0, 0.92))
        border.width: 1; border.color: Theme.line
        ColumnLayout {
          id: col
          anchors { fill: parent; margins: 16 }
          spacing: 12
          Text { text: "Authentication required"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15 * Theme.scale; font.weight: Font.Medium }
          Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.flow ? root.flow.message : ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
          Text {   // which account answers (when polkit offers several)
            visible: root.flow && root.flow.identities.length > 1
            text: root.flow && root.flow.selectedIdentity ? "as " + root.flow.selectedIdentity.displayName : ""
            color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 * Theme.scale
          }
          Rectangle {
            Layout.fillWidth: true; height: 34; radius: Theme.radiusInner
            color: "transparent"   // Nothing: an outlined field
            border.width: root.flow && root.flow.supplementaryIsError ? 2 : field.activeFocus ? 2 : 1
            border.color: root.flow && root.flow.supplementaryIsError ? Theme.red : field.activeFocus ? Theme.ring : Theme.edge
            TextInput {
              id: field
              anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
              verticalAlignment: TextInput.AlignVCenter
              echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              color: Theme.text; font.family: Theme.font; font.pixelSize: 15 * Theme.scale
              enabled: root.flow && root.flow.isResponseRequired
              focus: true
              onVisibleChanged: if (visible) forceActiveFocus()
              Keys.onReturnPressed: { root.flow.submit(text); text = "" }
              Keys.onEnterPressed: { root.flow.submit(text); text = "" }
              Keys.onEscapePressed: root.flow.cancelAuthenticationRequest()
              Text { visible: field.text === ""; anchors.verticalCenter: parent.verticalCenter; text: root.flow ? root.flow.inputPrompt : ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: 15 * Theme.scale }
            }
          }
          Text {
            visible: text !== ""
            text: root.flow ? root.flow.supplementaryMessage : ""
            color: root.flow && root.flow.supplementaryIsError ? Theme.red : Theme.dim
            font.family: Theme.font; font.pixelSize: 13 * Theme.scale
          }
          RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 10
            Rectangle {
              width: 84; height: 30; radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge
              Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.flow.cancelAuthenticationRequest() }
            }
            Rectangle {
              width: 110; height: 30; radius: Theme.radiusCtl; color: Theme.accent
              Text { anchors.centerIn: parent; text: "Authenticate"; color: Theme.accentInk; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.flow.submit(field.text); field.text = "" } }
            }
          }
        }
      }
    }
  }
}
