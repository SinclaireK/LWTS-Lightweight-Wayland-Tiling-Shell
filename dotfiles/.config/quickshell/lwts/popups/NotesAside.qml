// The Notes side panel of the time drop: it takes the calendar's place (TimePanel cross-fades them) and shows one of two lists chosen in the
// editor: "images" (the pictures attached to the open note) or "hints" (the key cheat-sheet). `pane` = the NotesPane item.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.widgets

Item {
  id: a
  property var pane
  readonly property string mode: pane ? pane.aside : ""
  readonly property var imgs: pane ? pane.curImages : []
  readonly property var keys: [["Ctrl+V", "Paste text / picture"], ["Right click", "Paste · copy · cut"], ["Drop files", "Attach images"], ["Ctrl+Space", "Checkbox on the line"],
                               ["Ctrl+N", "New note"], ["Delete ×2", "Remove note"], ["F1 / F2", "Keys / images list"], ["Esc", "Back / close"]]
  ColumnLayout {
    anchors.fill: parent; spacing: 8
    RowLayout {
      Layout.fillWidth: true
      UiCaption { text: a.mode === "images" ? "Images" : "Keys"; color: Theme.text }
      UiNum { visible: a.mode === "images"; text: a.imgs.length; size: Math.round(14 * Theme.scale); color: Theme.dim }
      Item { Layout.fillWidth: true }
      UiIconButton { icon: "x"; size: 22; onClicked: if (a.pane) a.pane.aside = "" }
    }
    UiDotLine { Layout.fillWidth: true }
    ListView {   // images: click = open full size, hover x = detach (the file stays in images/)
      visible: a.mode === "images"
      Layout.fillWidth: true; Layout.fillHeight: true
      clip: true; spacing: 6; boundsBehavior: Flickable.StopAtBounds; model: a.imgs
      add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
      remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
      displaced: Transition { NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } }
      delegate: Item {
        id: th
        required property string modelData
        required property int index
        width: ListView.view.width; height: 64
        Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: thMa.containsMouse ? Theme.fillHover : "transparent"; border.width: 1; border.color: Theme.edge }
        MouseArea { id: thMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(a.pane.imgUrl(th.modelData)) }
        Row {
          anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
          spacing: 10
          Image { width: 84; height: 56; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.height: 112; source: a.pane.imgUrl(th.modelData) }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 3
            UiCaption { text: "Image " + (th.index + 1); color: Theme.text }
            UiCaption { text: th.modelData.replace(/^.*\.(\w+)$/, "$1"); opacity: 0.7 }
          }
        }
        UiIconButton { visible: thMa.containsMouse; anchors { right: parent.right; top: parent.top; margins: 3 } icon: "x"; size: 22; onClicked: a.pane.dropImage(th.modelData) }
      }
      ColumnLayout {
        visible: parent.count === 0; anchors.centerIn: parent; spacing: 6
        UiNum { Layout.alignment: Qt.AlignHCenter; text: "00"; size: Math.round(32 * Theme.scale); opacity: 0.35 }
        UiCaption { Layout.alignment: Qt.AlignHCenter; text: "No images · Ctrl+V" }
      }
    }
    ColumnLayout {   // hints: a key chip + what it does
      visible: a.mode === "hints"; Layout.fillWidth: true; spacing: 7
      Repeater {
        model: a.keys
        RowLayout {
          required property var modelData
          Layout.fillWidth: true; spacing: 8
          Rectangle {
            Layout.preferredWidth: 78; Layout.preferredHeight: 20; radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge
            UiCaption { anchors.centerIn: parent; text: modelData[0]; color: Theme.text }
          }
          Text { Layout.fillWidth: true; text: modelData[1]; color: Theme.dim; elide: Text.ElideRight
                 font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
        }
      }
    }
    Item { Layout.fillHeight: true; visible: a.mode === "hints" }
  }
}
