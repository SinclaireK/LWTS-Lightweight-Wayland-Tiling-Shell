// Notification centre (bar: the dot, Super+N): Do not disturb, Clear all, the list (newest first).
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets
import "panelkeys.js" as PK

ColumnLayout {
  id: p
  spacing: 6
  focus: true
  property bool showHeader: true   // TimePanel draws its own tab strip instead
  readonly property bool wantsKeys: true
  signal closeMe()
  Keys.onPressed: e => { if (e.key === Qt.Key_Escape) closeMe(); else if (!PK.handle(p, e)) return; e.accepted = true }
  Component.onCompleted: Notifs.seen()
  RowLayout {   // Nothing header: caption + dot-matrix count, dotted rule
    visible: p.showHeader
    Layout.fillWidth: true
    spacing: 10
    UiCaption { text: "Notifications"; color: Theme.text }
    UiNum { text: Notifs.list.length; size: Math.round(16 * Theme.scale); color: Notifs.unread > 0 ? Theme.red : Theme.text }
  }
  UiDotLine { visible: p.showHeader; Layout.fillWidth: true }
  RowLayout {
    Layout.fillWidth: true
    ListRow { Layout.fillWidth: true; icon: "bell-slash"; title: "Do not disturb"; on: Notifs.dnd; onAct: Notifs.toggleDnd() }
    ListRow { implicitWidth: 80; icon: "trash"; title: "Clear"; visible: Notifs.list.length > 0; onAct: Notifs.clear() }
  }
  ColumnLayout {   // empty state: a big dot-matrix zero + a caption
    visible: Notifs.list.length === 0
    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 14; Layout.bottomMargin: 14
    spacing: 6
    UiNum { Layout.alignment: Qt.AlignHCenter; text: "00"; size: Math.round(40 * Theme.scale); opacity: 0.35 }
    UiCaption { Layout.alignment: Qt.AlignHCenter; text: "No notifications" }
  }
  Repeater {   // muted apps: Enter / click brings them back
    model: Notifs.muted
    ListRow { required property string modelData; Layout.fillWidth: true; icon: "bell-slash"; title: "Muted: " + modelData; trail: "Unmute"; onAct: Notifs.unmute(modelData) }
  }
  Flickable {
    id: flick
    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
    Layout.preferredHeight: Math.min(list.implicitHeight, 420)
    contentHeight: list.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    Column {
      id: list
      width: parent.width; spacing: 6
      Repeater { model: Notifs.list; NotifCard {
          required property var modelData
          n: modelData; width: list.width
          onFocusedChanged: if (focused) { if (y < flick.contentY) flick.contentY = y; else if (y + height > flick.contentY + flick.height) flick.contentY = y + height - flick.height }   // keep the picked card in view
        } }
    }
  }
}
