// A notification card (pop-ups and the centre): app icon / image, app · time, summary, body, action buttons.
// Click = open (default action or the app), right click / × = dismiss.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.core
import qs.services
import qs.widgets

MouseArea {
  id: c
  required property var n
  // the sender's picture (avatar, preview) keeps its colours; an icon-theme image (what Quickshell gives for the app icon) is the app icon
  readonly property string img: n && n.image ? String(n.image) : ""
  readonly property bool themed: img.startsWith("image://icon/") && !img.startsWith("image://icon//")   // a file path (screenshot preview) is a picture, not a themed icon
  readonly property string photo: img !== "" && !themed ? img : ""
  readonly property string appPic: themed ? img : (img === "" && n && n.appIcon ? Quickshell.iconPath(n.appIcon, true) : "")
  property bool focused: false   // keyboard (popups/panelkeys.js): Enter = open, Delete = dismiss, M = mute the app
  signal act()
  onAct: Notifs.open(n)
  function keyed(k) {
    if (k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_X) { Notifs.dismiss(n); return true }
    if (k === Qt.Key_M) { Notifs.mute(n); return true }
    return false
  }
  property bool timed: false   // pop-up: flat Nothing row (no plate of its own, the drop is the plate) + a dotted rule draining while it waits
  readonly property bool openable: Notifs.openable(n)
  readonly property var extra: n ? n.actions.filter(a => a.identifier !== "default") : []
  // pop-up x = hide the pop-up (stays in the centre); in the centre x = delete it
  function close() { timed ? Notifs.hide(n) : Notifs.dismiss(n) }
  implicitHeight: col.implicitHeight + (timed ? 14 : 16)
  hoverEnabled: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  // a click on the text opens only where there is something to open; it never silently closes. Right click = close.
  cursorShape: openable ? Qt.PointingHandCursor : Qt.ArrowCursor
  onClicked: m => m.button === Qt.RightButton ? c.close() : openable ? Notifs.open(n) : undefined
  readonly property bool critical: n && n.urgency === NotificationUrgency.Critical
  readonly property bool hot: c.containsMouse || c.focused
  Rectangle {
    anchors.fill: parent; radius: timed ? Theme.radiusCtl : Theme.radiusCard
    color: c.hot ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : timed ? "transparent" : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL2 * 0.4)
    border.width: c.focused ? 2 : timed ? 0 : 1; border.color: c.focused ? Theme.ring : c.critical ? Theme.red : Theme.line
  }
  onContainsMouseChanged: if (timed) Notifs.hold(n, containsMouse)
  UiDotLine {   // the resting rule between pop-ups
    visible: c.timed; strength: 0.22
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 8 }
  }
  UiDotLine {   // time left: the rule drains to the left; hover holds it (restarts full on leave)
    id: bar
    readonly property int life: c.timed && c.n ? Notifs.lifeOf(c.n) : 0
    visible: life > 0 && Prefs.get("notif_bar", true) !== false
    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8 }
    color: c.critical ? Theme.red : Theme.accent; strength: 0.9
    width: parent.width - 16
    NumberAnimation on width { running: bar.visible && !c.containsMouse; from: bar.parent.width - 16; to: 0; duration: bar.life }
  }
  RowLayout {
    anchors { fill: parent; margins: c.timed ? 7 : 8; bottomMargin: c.timed ? 8 : 8 }
    spacing: 9
    IconImage {   // image (avatar, preview): keeps its own colours
      Layout.alignment: Qt.AlignTop
      implicitSize: c.timed ? 30 : 36
      source: c.photo
      visible: source != "" && Prefs.get("notif_icon", true) !== false
    }
    AppIcon {   // the app icon: one ink, red only as a signal
      Layout.alignment: Qt.AlignTop
      size: c.timed ? 18 : 22
      source: c.appPic
      visible: source !== "" && Prefs.get("notif_icon", true) !== false
    }
    ColumnLayout {
      id: col
      Layout.fillWidth: true
      spacing: 2
      RowLayout {
        Layout.fillWidth: true
        spacing: 2
        Rectangle { visible: c.timed; Layout.rightMargin: 6; implicitWidth: 4; implicitHeight: 4; color: c.critical ? Theme.red : Theme.text }   // a lit LED dot (red: critical)
        UiCaption { Layout.fillWidth: true; elide: Text.ElideRight; color: c.critical ? Theme.red : Theme.dim
                    text: c.n ? [Prefs.get("notif_appname", true) !== false ? c.n.appName : "", Notifs.timeOf(c.n)].filter(x => x !== "").join(" · ") : "" }   // Nothing: APP · HH:MM in mono caps
        UiIconButton { visible: !c.timed && c.n && !!c.n.appName; icon: "bell-slash"; size: 18; onClicked: Notifs.mute(c.n) }   // mute this app (centre only; a pop-up keeps just the x)
        UiIconButton { icon: "x"; size: 18; onClicked: c.close() }
      }
      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: c.n ? c.n.summary : ""; color: Theme.text; font.weight: Font.DemiBold
             font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
      Text { Layout.fillWidth: true; visible: text !== "" && Number(Prefs.get("notif_lines", 3)) > 0; text: c.n ? c.n.body : ""; color: Theme.dim; wrapMode: Text.Wrap
             maximumLineCount: c.timed ? Math.min(2, Math.max(1, Number(Prefs.get("notif_lines", 3)))) : Math.max(1, Number(Prefs.get("notif_lines", 3)))
             elide: Text.ElideRight; textFormat: Text.PlainText; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
      Flow {   // the sender's own actions (a pop-up shows two at most, the centre all); a click on the text itself opens
        Layout.fillWidth: true; spacing: 4; Layout.topMargin: 4
        visible: c.extra.length > 0
        Repeater {
          model: c.timed ? c.extra.slice(0, 2) : c.extra
          UiButton {
            required property var modelData
            text: modelData.text
            onClicked: { const note = c.n; modelData.invoke(); Notifs.dismiss(note) }   // invoke() can close the notification and free this card first
          }
        }
      }
    }
  }
}
