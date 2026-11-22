// Notes (Mod+Shift+N): cards with clickable "[ ]" checkboxes, in the style of AngelOS-Dotfiles (MIT). Type to filter, ↑/↓ choose,
// Enter or a click opens the editor, Esc leaves it (and closes the panel from the list), Ctrl+N new, Delete twice removes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.services

Scope {
  id: root
  property bool shown: false
  function toggle() { shown = !shown }
  Component.onCompleted: Notes.ready
  IpcHandler { target: "notes"; function toggle(): void { root.toggle() } }

  Variants {
    model: root.shown ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-osd"
      BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null
      Region { id: blurRgn; item: plate; radius: Theme.radius }
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.25)
      MouseArea { anchors.fill: parent; onClicked: root.shown = false }
      Component.onDestruction: if (tab.editing) tab.close()

      Rectangle {
        id: plate
        width: 560; height: Math.min(win.height * 0.6, 460)
        x: (parent.width - width) / 2; y: parent.height / 4
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.max(Theme.opacityL0, 0.92))
        border.width: 1; border.color: Theme.line
        MouseArea { anchors.fill: parent }
        ColumnLayout {
          anchors { fill: parent; margins: 8 }
          spacing: 8
          RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 10
            TextInput {
              id: search
              Layout.fillWidth: true; Layout.preferredHeight: 40
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text; font.family: Theme.font; font.pixelSize: 16 * Theme.scale
              focus: true; enabled: tab.editing === 0
              onVisibleChanged: if (visible) forceActiveFocus()
              onTextChanged: { tab.sel = 0; tab.query = text }
              Keys.onEscapePressed: root.shown = false
              Keys.onUpPressed: tab.move(-1)
              Keys.onDownPressed: tab.move(1)
              Keys.onReturnPressed: tab.openSel()
              Keys.onDeletePressed: tab.removeSel()
              Keys.onPressed: e => { if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_N) { tab.create(); e.accepted = true } }
              Text { visible: search.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Notes"; color: Theme.dim; font: search.font }
            }
            Rectangle {
              Layout.preferredWidth: add.implicitWidth + 16; Layout.preferredHeight: 26; Layout.rightMargin: 4; radius: Theme.radiusCtl
              color: addHov.containsMouse ? Theme.fillHover : "transparent"; border.width: 1; border.color: Theme.edge
              Text { id: add; anchors.centerIn: parent; text: "+ New"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 * Theme.scale }
              MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true; onClicked: tab.create() }
            }
          }
          NotesTab {
            id: tab
            Layout.fillWidth: true; Layout.fillHeight: true
            onLeave: search.forceActiveFocus()
          }
        }
      }
    }
  }
}
