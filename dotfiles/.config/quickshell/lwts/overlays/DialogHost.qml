// Draws services/Prompt.qml: a centred plate on the focused monitor, keys: ←/→ or ↑/↓ move, Enter accepts, Esc closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

Scope {
  Component.onCompleted: console.warn('DIALOGHOST shown=', Prompt.shown, 'lock=', Lock.want)
  Variants {
    model: Prompt.shown ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-osd"
      BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null   // glass only behind the plate
      Region { id: blurRgn; item: blurPlate; radius: Theme.radius }
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.3)
      MouseArea { anchors.fill: parent; onClicked: Prompt.close() }
      FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Prompt.close()
        Keys.onPressed: e => {
          const n = Prompt.items.length ? Prompt.items.length : 2;
          if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) Prompt.sel = (Prompt.sel + n - 1) % n;
          else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) Prompt.sel = (Prompt.sel + 1) % n;
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) Prompt.accept(Prompt.sel);
          else if (!Prompt.items.length && e.key === Qt.Key_Y) Prompt.accept(1);
          else if (!Prompt.items.length && e.key === Qt.Key_N) Prompt.close();
        }
        Rectangle {
          id: blurPlate
          anchors.centerIn: parent
          width: Math.max(320, col.implicitWidth + 40); height: col.implicitHeight + 40
          radius: Theme.radius
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.max(Theme.opacityL0, 0.9))
          border.width: 1; border.color: Theme.line
          ColumnLayout {
            id: col
            anchors { fill: parent; margins: 20 }
            spacing: 12
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Prompt.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 16 * Theme.scale; font.weight: Font.Medium }
            Repeater {   // list
              model: Prompt.items
              Rectangle {
                required property string modelData
                required property int index
                Layout.fillWidth: true; height: 34; radius: Theme.radiusInner
                color: Prompt.sel === index ? Theme.tint : "transparent"
                Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 } text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: Prompt.sel = index; onClicked: Prompt.accept(index) }
              }
            }
            RowLayout {   // Yes / No
              visible: Prompt.items.length === 0
              Layout.alignment: Qt.AlignRight
              spacing: 10
              Repeater {
                model: ["No", "Yes"]
                Rectangle {
                  required property string modelData
                  required property int index
                  width: 90; height: 34; radius: Theme.radiusInner
                  color: Prompt.sel === index ? Theme.accent : Theme.fill
                  Text { anchors.centerIn: parent; text: modelData; color: Prompt.sel === index ? Theme.accentInk : Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
                  MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: Prompt.sel = index; onClicked: Prompt.accept(index) }
                }
              }
            }
          }
        }
      }
    }
  }
}
