// Screen-share picker: the window an app's "share screen" opens (replaces the GNOME portal dialog).
// The portal backend `lwts-portal` connects to $XDG_RUNTIME_DIR/lwts-castpick.sock, sends one JSON line
// {app, types (1 screens, 2 windows, 3 both), multiple, cursor} and waits for {ok, sources:[{type:"monitor",name}|{type:"window",id}], cursor}.
// Panel style (concepts/panel-style.md): one glass plate, key/value rows (UiKvRow), dotted rules, quiet chips; no cards, no boxes.
// No ScreencopyView previews: it crashed the whole shell (dmabuf texture destroyed while in use, 2026-11-12).
// Keys: Up/Down move, Space marks (several allowed), Enter shares, Esc cancels; click marks, double click shares.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.services
import qs.widgets

Scope {
  id: root
  property var req: null              // the request being answered (null = closed)
  property var conn: null             // its socket
  property int cur: 0                 // keyboard / hover position in `items`
  property var picked: []             // item indices marked (several-sources apps)
  property bool cursorOn: true

  readonly property bool wantScreens: !!req && (req.types & 1) !== 0
  readonly property bool wantWindows: !!req && (req.types & 2) !== 0
  readonly property bool multi: !!req && req.multiple === true
  readonly property var screens: wantScreens ? Quickshell.screens.map(s => ({ kind: "monitor", name: s.name, screen: s, title: s.name, label: s.name, label: s.name,
    sub: s.width + " x " + s.height, glyph: s.width < s.height ? "screen-v" : "screen" })) : []
  readonly property var wins: wantWindows ? Compositor.windowList.slice().sort((a, b) => (b.is_focused ? 1 : 0) - (a.is_focused ? 1 : 0) || a.id - b.id)
    .map(w => { const e = DesktopEntries.heuristicLookup(w.app_id || ""); return { kind: "window", id: w.id, title: w.title || w.app_id || "Window", label: e ? e.name : (w.app_id || "Window"), sub: w.app_id || "", glyph: e ? Kinds.ofEntry(e) : Kinds.ofProcess(w.app_id || ""), icon: e ? Quickshell.iconPath(e.icon || "", true) : "" } }) : []
  readonly property var items: screens.concat(wins).slice(0, 12)   // 3 columns x 4 rows; no scrolling

  function open(sock, r) {
    if (req) { sock.write('{"cancel":true}\n'); sock.flush(); return }   // one picker at a time
    conn = sock; req = r; picked = []; cur = 0; cursorOn = r.cursor !== 1
  }
  function answer(ok) {
    const c = conn;
    if (c) {
      let msg = { ok: false };
      if (ok && items.length) {
        const idx = picked.length ? picked.slice().sort((a, b) => a - b) : [Math.max(0, Math.min(cur, items.length - 1))];
        msg = { ok: true, cursor: req.cursor === 4 ? 4 : cursorOn ? 2 : 1,
                sources: idx.map(i => items[i].kind === "window" ? { type: "window", id: items[i].id } : { type: "monitor", name: items[i].name }) };
      }
      c.write(JSON.stringify(msg) + "\n"); c.flush();
    }
    req = null; conn = null
  }
  function mark(i) {
    cur = i;
    if (!multi) { picked = [i]; return }
    const k = picked.indexOf(i);
    picked = k >= 0 ? picked.filter(x => x !== i) : picked.concat([i])
  }
  readonly property int cols: 3
  readonly property real screenW: screens.length ? Math.floor((360 - 6 * (screens.length - 1)) / screens.length) : 0   // screens share the first row
  function move(dx, dy) {   // screens: one row sharing the width; windows: rows of `cols`
    const ns = screens.length, n = items.length;
    if (!n) return;
    if (dx) { cur = Math.max(0, Math.min(n - 1, cur + dx)); return }
    if (dy > 0) { if (cur < ns) { if (n > ns) cur = ns } else cur = Math.min(n - 1, cur + cols) }
    else if (cur >= ns) { if (cur - cols >= ns) cur -= cols; else if (ns) cur = Math.min(ns - 1, Math.floor(((cur - ns) % cols) * ns / cols)) }
  }

  IpcHandler {   // scripts / tests: `qs -c lwts ipc call castpicker confirm|cancel`
    target: "castpicker"
    function confirm(): void { if (root.req) root.answer(true) }
    function cancel(): void { if (root.req) root.answer(false) }
  }

  // a shell reload creates the new socket first and the old server then unlinks the same path: re-create it once the old one is gone
  Timer { running: true; interval: 1500; onTriggered: { srv.active = false; srv.active = true } }
  SocketServer {
    id: srv
    active: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/lwts-castpick.sock"
    handler: Socket {
      id: sk
      parser: SplitParser {
        onRead: line => {
          let m = null;
          try { m = JSON.parse(line) } catch (e) { return }
          if (m.cancel) { if (root.conn === sk) { root.req = null; root.conn = null } }   // the app gave up
          else root.open(sk, m)
        }
      }
      onConnectedChanged: if (!connected && root.conn === sk) { root.req = null; root.conn = null }
    }
  }

  Variants {
    model: root.req ? Quickshell.screens.filter(s => s.name === Compositor.focusedOutput).concat(Quickshell.screens).slice(0, 1) : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-castpicker"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: Qt.rgba(0, 0, 0, 0.35)
      BackgroundEffect.blurRegion: Prefs.blurOn ? blurRgn : null
      Region { id: blurRgn; item: plate; radius: Theme.radius }

      MouseArea { anchors.fill: parent; onClicked: root.answer(false) }   // outside the plate = cancel

      FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
          if (e.key === Qt.Key_Escape) root.answer(false)
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.answer(true)
          else if (e.key === Qt.Key_Space) root.mark(root.cur)
          else if (e.key === Qt.Key_Left) root.move(-1, 0)
          else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.move(1, 0)
          else if (e.key === Qt.Key_Up) root.move(0, -1)
          else if (e.key === Qt.Key_Down) root.move(0, 1)
          else return;
          e.accepted = true
        }

        Rectangle {
          id: plate
          anchors.centerIn: parent
          width: 400; height: col.implicitHeight + 32
          radius: Theme.radius
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
          border.width: 1; border.color: Theme.line
          MouseArea { anchors.fill: parent }   // clicks on the plate do not cancel

          ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 8

            RowLayout {   // header like the launcher's: caption lines on the left, the one dot-matrix hero (the current target) on the right
              Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.bottomMargin: 2
              spacing: 10
              ColumnLayout {
                spacing: 3
                UiCaption { text: "Screen share"; color: Theme.text; font.pixelSize: Math.round(12 * Theme.scale) }
                UiCaption { text: root.req && root.req.app ? root.req.app + " asks" : "An app asks" }
              }
              Item { Layout.fillWidth: true }
              Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 3; width: 4; height: 4; radius: 2; color: Theme.red }   // the red signal dot, as by the clock
              UiNum {
                readonly property var it: root.items[root.cur] || null
                text: !it ? "--" : it.kind === "monitor" ? it.name : (it.label || "WIN").replace(/[^A-Za-z0-9]+/g, " ").trim().split(" ")[0].slice(0, 8).toUpperCase()
                size: Math.round(28 * Theme.scale)
              }
            }
            UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }

            Flow {   // every screen and window is one dot glyph (the launcher's kind icons); the name lives in the hero and the line below
              Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
              spacing: 6
              Repeater {
                model: root.items
                MouseArea {
                  id: cell
                  required property var modelData
                  required property int index
                  readonly property bool hot: root.cur === index
                  readonly property bool on: root.picked.indexOf(index) >= 0
                  width: modelData.kind === "monitor" ? root.screenW : 116; height: 34
                  hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) root.cur = index
                  onClicked: root.mark(index)
                  onDoubleClicked: { root.mark(index); root.answer(true) }
                  Rectangle {
                    anchors.fill: parent; radius: Theme.radiusCtl
                    color: cell.containsMouse ? Theme.fillHover : "transparent"
                    border.width: cell.hot ? 2 : 0; border.color: Theme.ring
                  }
                  Item {   // the app's own icon as a dot matrix; no icon (or a screen): the kind glyph
                    id: gl
                    width: 20; height: 20
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    AppIcon { visible: !!cell.modelData.icon; source: cell.modelData.icon || ""; size: 20; ink: cell.hot || cell.on ? Theme.text : Theme.dim }
                    UiKindIcon { visible: !cell.modelData.icon; kind: cell.modelData.glyph; dot: 2; gap: 1
                                 color: cell.hot || cell.on ? Theme.text : Theme.dim }
                  }
                  Text {   // the short name: the app (windows) or the connector (screens); the full title is in the line below
                    anchors { left: gl.right; right: mark.left; leftMargin: 8; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: cell.modelData.label; elide: Text.ElideRight
                    color: cell.hot || cell.on ? Theme.text : Theme.dim
                    font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
                  }
                  Rectangle { id: mark; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } width: 4; height: 4; radius: 2; color: Theme.red; opacity: cell.on ? 1 : 0 }
                }
              }
            }
            UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
            UiKvRow {   // what the cursor is on, in full
              readonly property var it: root.items[root.cur] || null
              Layout.fillWidth: true
              key: !it ? "" : it.kind === "monitor" ? "SCREEN" : "WINDOW"
              value: !it ? "" : it.title + (it.kind === "monitor" ? "  " + it.sub : "")
              onAct: root.answer(true)
            }
            UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
            RowLayout {
              Layout.fillWidth: true; spacing: 4
              UiChip { text: "Cursor"; visible: !root.req || root.req.cursor !== 4; on: root.cursorOn; onAct: root.cursorOn = !root.cursorOn }
              Item { Layout.fillWidth: true }
              UiButton { text: "Cancel"; onClicked: root.answer(false) }
              UiButton { text: "Share"; on: true; onClicked: root.answer(true) }
            }
          }
        }
      }
    }
  }
}
