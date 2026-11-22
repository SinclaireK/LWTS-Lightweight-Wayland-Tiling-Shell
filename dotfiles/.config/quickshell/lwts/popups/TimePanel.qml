// The time shade: two pages of the launcher drop (Launcher.qml timeLoader; `tab` is set by the header's page switch).
//  notif: notification centre (340) | calendar + Today block (252)      notes: list (230) | editor (362)
// Both pages have the same size (617 x 420) so the drop never resizes between them; only the content changes.
// Standalone "clock" / "notif" drops (split mode) still use CalendarPanel / NotifCenter on their own.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

FocusScope {
  id: p
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  signal page(int d)   // Tab / Shift+Tab: the launcher steps its pages (Quick settings, Notifications, Notes)
  readonly property int bodyW: 617
  readonly property int bodyH: 420
  implicitWidth: bodyW
  implicitHeight: bodyH
  readonly property real dropWidth: implicitWidth + 24   // Popups: 12 px margin each side
  readonly property bool keepOpen: tab === "notes"   // typing in Notes: the drop must not close when the cursor wanders off (Popups: leave timer)
  property string tab: "notif"   // notif | notes; set by the launcher header's page switch
  property date day: new Date()   // the day picked in the calendar: the Today block shows it
  readonly property bool notesOk: Modules.enabled("notes")
  property real tabK: 1   // the page's content rises + fades in on every page switch
  NumberAnimation { id: tabIn; target: p; property: "tabK"; from: 0; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve }
  onTabChanged: { tabIn.restart(); if (tab === "notif") { Notifs.seen(); Qt.callLater(() => center.forceActiveFocus()) } }
  Keys.onPressed: e => {
    if (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier) && tab === "notif" && agenda.item) { agenda.item.focusAdd(); e.accepted = true }   // Ctrl+N: a new item in the Today block
    else if (e.key === Qt.Key_Tab) { p.page(1); e.accepted = true }   // Tab = next page
    else if (e.key === Qt.Key_Backtab) { p.page(-1); e.accepted = true }   // Shift+Tab = previous (the Notes pane keeps its own keys)
  }
  // entrance: notifications, hairline, calendar come in one after another (rise 8 px + fade), the calendar last: it sits under the bar clock
  property real k1: 0
  property real k2: 0
  property real k3: 0
  Component.onCompleted: enter.start()
  ParallelAnimation {
    id: enter
    SequentialAnimation { NumberAnimation { target: p; property: "k1"; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } }
    SequentialAnimation { PauseAnimation { duration: Math.round(Motion.fast * 0.35) }
      NumberAnimation { target: p; property: "k2"; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } }
    SequentialAnimation { PauseAnimation { duration: Math.round(Motion.fast * 0.7) }
      NumberAnimation { target: p; property: "k3"; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve } }
  }

  RowLayout {   // page: notifications | calendar + Today
    id: notifPage
    anchors.fill: parent
    visible: p.tab === "notif"
    spacing: 12
    NotifCenter {
      id: center
      Layout.preferredWidth: 340; Layout.fillHeight: true; Layout.alignment: Qt.AlignTop
      showHeader: false
      opacity: p.k1 * p.tabK; transform: Translate { y: (1 - p.k1 * p.tabK) * 8 }
      onCloseMe: p.closeMe()
    }
    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.line; opacity: p.k2 }   // hairline between the two
    ColumnLayout {   // right: the month, then today's classes and the weather
      Layout.preferredWidth: 252; Layout.fillHeight: true; Layout.alignment: Qt.AlignTop
      spacing: 8
      opacity: p.k3 * p.tabK; transform: Translate { y: (1 - p.k3 * p.tabK) * 8 }
      CalendarPanel { cellW: 34; cellH: 20; Layout.fillWidth: true; selected: p.day; marks: agenda.item ? agenda.item.marks : ({}); onPicked: d => p.day = d }
      UiDotLine { Layout.fillWidth: true; visible: agenda.visible }
      Loader {
        id: agenda
        active: Modules.enabled("dataw")
        visible: active && !!item && item.has
        Layout.fillWidth: true
        source: "AgendaPanel.qml"
        onLoaded: item.day = Qt.binding(() => p.day)
      }
      Item { Layout.fillHeight: true }
    }
  }

  Connections { target: agenda.item; ignoreUnknownSignals: true; function onLeave() { center.forceActiveFocus() } function onReset() { p.day = new Date() } }

  Loader {   // page: the notes (list | editor), built only while this page is open
    id: notesLoader
    anchors.fill: parent
    active: p.tab === "notes" && p.notesOk
    visible: active
    opacity: p.tabK; transform: Translate { y: (1 - p.tabK) * 6 }
    source: "NotesPane.qml"
    onLoaded: item.forceActiveFocus()
  }
  Connections { target: notesLoader.item; ignoreUnknownSignals: true; function onCloseDrop() { p.closeMe() } }
}
