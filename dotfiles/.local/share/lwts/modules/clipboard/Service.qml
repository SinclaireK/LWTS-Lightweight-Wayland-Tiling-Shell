// Clipboard history panel (Super+V): search, ↑/↓ choose, Enter copies it back, Delete removes, Esc closes.
// Opens on the focused monitor, centred in the upper third (same place as the launcher plate).
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
  Component.onCompleted: Clip.ready   // touching the singleton starts its wl-paste watcher at shell start
  IpcHandler { target: "clip"; function toggle(): void { root.toggle() } function clear(): void { Clip.clear() } }

  Variants {
    model: root.shown ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-osd"
      BackgroundEffect.blurRegion: Region { item: blurPlate; radius: Theme.radius }   // glass only behind the plate
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.25)
      MouseArea { anchors.fill: parent; onClicked: root.shown = false }

      property int sel: 0
      property string kind: "all"   // all | text | image | fav (Tab cycles)
      readonly property var kinds: [["all", "All"], ["text", "Text"], ["image", "Images"], ["fav", "★"]]
      readonly property var shownItems: {
        const q = search.text.toLowerCase();
        const l = [];
        for (let i = 0; i < Clip.items.length; i++) {
          const x = Clip.items[i];
          if (kind === "fav" ? !x.fav : kind !== "all" && x.t !== kind) continue;
          if (q === "" || (x.t === "text" && x.s.toLowerCase().indexOf(q) >= 0) || (x.t === "image" && "image".indexOf(q) >= 0)) l.push({ i, x });
        }
        return l;
      }
      Rectangle {
        id: blurPlate
        width: 560; height: Math.min(win.height * 0.6, 86 + Math.max(1, win.shownItems.length) * 38 + 16)
        x: (parent.width - width) / 2; y: parent.height / 4
        radius: Theme.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.max(Theme.opacityL0, 0.92))
        border.width: 1; border.color: Theme.line
        MouseArea { anchors.fill: parent }   // clicks inside do not reach the closer behind
        ColumnLayout {
          anchors { fill: parent; margins: 8 }
          spacing: 8
          TextInput {
            id: search
            Layout.fillWidth: true; Layout.preferredHeight: 40; Layout.leftMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; font.family: Theme.font; font.pixelSize: 16 * Theme.scale
            focus: true
            onVisibleChanged: if (visible) forceActiveFocus()
            onTextChanged: win.sel = 0
            Keys.onTabPressed: { const k = win.kinds.map(x => x[0]); win.kind = k[(k.indexOf(win.kind) + 1) % k.length]; win.sel = 0 }
            Keys.onPressed: e => { if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_D) { const it = win.shownItems[win.sel]; if (it) Clip.toggleFav(it.i); e.accepted = true } }
            Keys.onEscapePressed: root.shown = false
            Keys.onUpPressed: win.sel = Math.max(0, win.sel - 1)
            Keys.onDownPressed: win.sel = Math.min(win.shownItems.length - 1, win.sel + 1)
            Keys.onReturnPressed: { const it = win.shownItems[win.sel]; if (it) { Clip.copy(it.i); root.shown = false } }
            Keys.onDeletePressed: { const it = win.shownItems[win.sel]; if (it) Clip.remove(it.i) }
            Text { visible: search.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Clipboard history"; color: Theme.dim; font: search.font }
          }
          Row {
            Layout.leftMargin: 10; spacing: 6
            Repeater {
              model: win.kinds
              Rectangle {
                required property var modelData
                width: chip.implicitWidth + 16; height: 22; radius: Theme.radiusInner
                color: win.kind === modelData[0] ? Theme.tint : "transparent"
                border.width: 1; border.color: Theme.line
                Text { id: chip; anchors.centerIn: parent; text: modelData[0] === "fav" ? "★ " + Clip.favCount : modelData[1]; color: win.kind === modelData[0] ? Theme.text : Theme.dim
                       font.family: Theme.font; font.pixelSize: 12 * Theme.scale }
                MouseArea { anchors.fill: parent; onClicked: { win.kind = modelData[0]; win.sel = 0; search.forceActiveFocus() } }
              }
            }
            Text { anchors.verticalCenter: undefined; text: "Tab · Ctrl+D ★"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 11 * Theme.scale; leftPadding: 8; height: 22; verticalAlignment: Text.AlignVCenter }
          }
          ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 2
            model: win.shownItems
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: ListView.view.width; height: 36; radius: Theme.radiusInner
              color: win.sel === index ? Theme.tint : "transparent"
              Row {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 10
                Image {
                  visible: modelData.x.t === "image"; width: visible ? 30 : 0; height: 30; anchors.verticalCenter: parent.verticalCenter
                  source: visible ? "file://" + modelData.x.f : ""; sourceSize: Qt.size(60, 60); fillMode: Image.PreserveAspectCrop; asynchronous: true
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52
                  elide: Text.ElideRight; maximumLineCount: 1
                  text: modelData.x.t === "text" ? modelData.x.s.replace(/\s+/g, " ").trim() : "Image"
                  color: Theme.text; font.family: Theme.font; font.pixelSize: 14 * Theme.scale
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter; width: 22; horizontalAlignment: Text.AlignHCenter
                  text: modelData.x.fav ? "★" : "☆"; visible: modelData.x.fav || win.sel === index
                  color: modelData.x.fav ? Theme.accent : Theme.dim; font.pixelSize: 15 * Theme.scale
                  MouseArea { anchors.fill: parent; onClicked: Clip.toggleFav(modelData.i) }
                }
              }
              MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: win.sel = index; onClicked: { Clip.copy(modelData.i); root.shown = false } }
            }
            Text { visible: parent.count === 0; anchors.centerIn: parent; text: Clip.ready ? "Nothing here yet" : "…"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 14 * Theme.scale }
          }
        }
      }
    }
  }
}
