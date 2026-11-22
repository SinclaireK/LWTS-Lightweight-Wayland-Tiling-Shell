// Alt+Tab window switcher in the LWTS look. niri binds Alt+Tab / Alt+Shift+Tab -> `qs -c lwts ipc call switcher next|prev`; every further Tab
// (a new bind trigger) steps on, and letting go of Alt picks the window. Order = most recently used first (the first press lands on the
// previous window). Esc cancels, Enter / click picks. Shows every window of every workspace.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.core
import qs.widgets
import qs.services

Scope {
  id: root
  property bool active: false
  property bool sticky: false     // `show` (debug): no auto-pick on Alt release
  property var list: []
  property int idx: 0
  property bool sawAlt: false
  property var mru: []            // window ids, most recent first (kept from the focus changes the shell sees)

  Connections {
    target: Compositor
    function onFocusedWindowIdChanged() { const id = Compositor.focusedWindowId; if (id >= 0 && !root.active) root.mru = [id].concat(root.mru.filter(x => x !== id)) }
  }
  function ts(w) { const f = w.focus_timestamp; return f ? f.secs * 1e9 + f.nanos : 0 }
  function build() {
    const all = Compositor.windowList.slice(), byId = {};
    for (const w of all) byId[w.id] = w;
    const first = mru.filter(id => byId[id]).map(id => byId[id]);
    const rest = all.filter(w => !mru.includes(w.id)).sort((a, b) => ts(b) - ts(a));
    return first.concat(rest);
  }
  function step(d) {
    if (!active) {
      list = build();
      if (list.length === 0) return;
      idx = list.length > 1 ? (d > 0 ? 1 : list.length - 1) : 0;
      sawAlt = false; sticky = false; active = true; grace.restart();
    } else idx = (idx + d + list.length) % list.length;
  }
  function pick() { const w = list[idx]; active = false; grace.stop(); if (w) Compositor.focusWindow(w.id) }
  function cancel() { active = false; grace.stop() }

  IpcHandler {
    target: "switcher"
    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
    function abort(): void { root.cancel() }
    function hold(): void { root.step(1); root.sticky = true }   // test: stays open until Enter / Esc / click
  }
  Timer {   // Alt already let go before the overlay got the keyboard: pick at once
    id: grace; interval: 250
    onTriggered: if (root.active && !root.sawAlt && !root.sticky) root.pick()
  }
  Timer {   // Qt keeps the modifier state of the focused surface: Alt gone after it was seen = pick
    running: root.active; interval: 30; repeat: true
    onTriggered: {
      const alt = (Qt.application.keyboardModifiers & Qt.AltModifier) !== 0;
      if (alt) root.sawAlt = true; else if (root.sawAlt && !root.sticky) root.pick();
    }
  }

  Variants {
    model: root.active ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-switcher"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.25)

      readonly property int maxShown: 7
      readonly property int first: Math.max(0, Math.min(root.list.length - maxShown, root.idx - Math.floor(maxShown / 2)))   // the window of cards around the pick
      readonly property var shown: root.list.slice(first, first + maxShown)

      MouseArea { anchors.fill: parent; onClicked: root.cancel() }
      Rectangle {
        id: plate
        anchors.centerIn: parent
        width: cards.implicitWidth + 28; height: cards.implicitHeight + 28
        radius: Theme.radiusCard
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.width: 1; border.color: Theme.line
        scale: 1; opacity: 1
        Component.onCompleted: { scale = 0.94; opacity = 0; enter.start() }
        ParallelAnimation {
          id: enter
          NumberAnimation { target: plate; property: "scale"; to: 1; duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve }
          NumberAnimation { target: plate; property: "opacity"; to: 1; duration: Motion.duration }
        }
        Row {
          id: cards
          anchors.centerIn: parent
          spacing: 8
          Repeater {
            model: win.shown
            Item {
              id: card
              required property var modelData
              required property int index
              readonly property bool on: win.first + index === root.idx
              readonly property var entry: DesktopEntries.heuristicLookup(modelData.app_id || "")
              width: 132; height: 112
              scale: on ? 1.04 : 1
              Behavior on scale { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
              Rectangle {
                anchors.fill: parent; radius: Theme.radiusCtl
                color: card.on ? Theme.fillHover : "transparent"; border.width: card.on ? 1 : 0; border.color: Theme.text   // Nothing: the pick = a white outline
                Behavior on color { ColorAnimation { duration: Motion.duration } }
              }
              Rectangle {
                anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"; border.width: 2; border.color: Theme.ring
                opacity: card.on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.duration } }
              }
              Column {
                anchors { fill: parent; margins: 8 }
                spacing: 6
                AppIcon {
                  anchors.horizontalCenter: parent.horizontalCenter
                  size: 48
                  source: Quickshell.iconPath(card.entry ? card.entry.icon : (card.modelData.app_id || ""), "application-x-executable")
                }
                Text {
                  width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                  text: card.entry ? card.entry.name : (card.modelData.app_id || "?")
                  color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale)
                }
                Text {
                  width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                  text: card.modelData.title || ""
                  color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
                }
              }
              MouseArea { anchors.fill: parent; onClicked: { root.idx = win.first + card.index; root.pick() } }
            }
          }
        }
      }
      Item {
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: e => {
          if (e.key === Qt.Key_Escape) root.cancel();
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.pick();
          else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_Down) root.step(1);
          else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left || e.key === Qt.Key_Up) root.step(-1);
          else return;
          e.accepted = true;
        }
      }
    }
  }
}
