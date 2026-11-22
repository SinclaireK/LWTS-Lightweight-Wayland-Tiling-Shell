// Gamepad tab, the live picture of the part being tuned (Big Picture style, Nothing look: outlines, dots, mono caps, Doto).
//   o     : overview, the whole pad live: both sticks (hollow = hand, solid = game), both triggers, every button;
//   l / r : the stick circle (drag a ring: deadzone / outer deadzone) and the response graph (drag: curve);
//   t     : both triggers as dot columns (drag the Start / Full marks).
// Drags preview live and save on release (snapped to the slider steps); the sliders below stay for the keyboard.
// Values: settings/components/PadSource.qml (raw), processed by PadCal (the same maths as lwts-padd).
import QtQuick
import Quickshell.Io
import qs.core
import qs.services
import qs.widgets

Item {
  id: v
  property var pad: null
  property string part: "o"
  implicitHeight: Math.round((part === "o" ? 200 : part === "t" ? 180 : 178) * Theme.scale)   // the tab fits without scrolling

  PadSource { id: src; pad: v.pad; onUpdated: v.tick++ }
  property int tick: 0
  property var draft: ({})   // tuning being dragged: shown at once, saved on release
  readonly property var t: { void Prefs.get(PadCal.tkey(pad ? pad.id : "-"), ""); return Object.assign(pad ? PadCal.tune(pad.id) : Object.assign({}, PadCal.tuneDefaults), draft) }
  readonly property int calRev: { void Prefs.get(PadCal.key(pad ? pad.id : "-"), ""); return tick }   // re-read after a centre change
  function stickIn(i) { void calRev; return pad ? PadCal.stickIn(pad, i, src.raw) : [0, 0] }
  readonly property var trig: { void calRev; return pad ? [PadCal.trigIn(pad, 0, src.raw), PadCal.trigIn(pad, 1, src.raw)] : [0, 0] }
  readonly property var bmap: { void Prefs.get(PadCal.skey("btn", pad ? pad.id : "-"), ""); return pad ? PadCal.btnMap(pad.id) : ({}) }   // rebinding: lit as the game sees it
  function held(code) { void tick; for (const k in src.keys) if (src.keys[k] && (bmap[k] !== undefined ? bmap[k] : Number(k)) === code) return true; return false }
  readonly property int hx: { void tick; return src.raw[16] || 0 }
  readonly property int hy: { void tick; return src.raw[17] || 0 }

  // drag helpers: snap to the slider steps (SettingsNew padRows), save once on release
  readonly property var steps: ({ dz: [0, 2, 4, 6, 8, 10, 12, 15, 20, 25, 30], out: [0, 2, 4, 6, 8, 10, 15, 20],
                                  curve: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], ts: [0, 2, 5, 8, 10, 15, 20, 30, 40, 50], te: [50, 60, 70, 80, 85, 90, 95, 100] })
  function snap(list, x) { return list.reduce((a, b) => Math.abs(b - x) < Math.abs(a - x) ? b : a) }
  function preview(name, kind, x) { const d = Object.assign({}, draft); d[name] = snap(steps[kind], x); draft = d }
  function commit() { if (pad && Object.keys(draft).length) PadCal.setTunes(pad, draft); draft = {} }

  component Read: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }

  // ---- overview: the whole pad ----
  Column {
    visible: v.part === "o"
    anchors.centerIn: parent
    spacing: 10
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Math.round(18 * Theme.scale)
      Column {   // left: LB, LT, stick
        spacing: 8
        Row { spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
              UiButton { padX: 10; text: "LB"; on: v.held(310); anchors.verticalCenter: parent.verticalCenter }
              Read { text: "LT " + Math.round(PadCal.trigOut(v.t, "l", v.trig[0]) * 100) + "%"; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 8
              PadTrigger { view: v; which: 0; h: Math.round(100 * Theme.scale); anchors.verticalCenter: parent.verticalCenter }
              PadStick { view: v; stick: 0; d: Math.round(108 * Theme.scale); rings: false } }
      }
      Column {   // centre: menu buttons, d-pad, face buttons
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
              UiButton { padX: 10; text: "Sel"; on: v.held(314) } UiButton { padX: 10; text: "Home"; on: v.held(316) } UiButton { padX: 10; text: "Start"; on: v.held(315) } }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: 16
          Grid {   // d-pad: hat on most pads, buttons on some
            columns: 3; spacing: 2
            Item { width: 22; height: 22 } UiButton { padX: 10; text: "↑"; on: v.hy < 0 || v.held(544) } Item { width: 22; height: 22 }
            UiButton { padX: 10; text: "←"; on: v.hx < 0 || v.held(546) } Item { width: 22; height: 22 } UiButton { padX: 10; text: "→"; on: v.hx > 0 || v.held(547) }
            Item { width: 22; height: 22 } UiButton { padX: 10; text: "↓"; on: v.hy > 0 || v.held(545) } Item { width: 22; height: 22 }
          }
          Grid {   // face buttons, Xbox layout
            columns: 3; spacing: 2
            Item { width: 22; height: 22 } UiButton { padX: 10; text: "Y"; on: v.held(308) } Item { width: 22; height: 22 }
            UiButton { padX: 10; text: "X"; on: v.held(307) } Item { width: 22; height: 22 } UiButton { padX: 10; text: "B"; on: v.held(305) }
            Item { width: 22; height: 22 } UiButton { padX: 10; text: "A"; on: v.held(304) } Item { width: 22; height: 22 }
          }
        }
        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 4
              UiButton { padX: 10; text: "L3"; on: v.held(317) } UiButton { padX: 10; text: "R3"; on: v.held(318) } }
      }
      Column {   // right: RB, RT, stick
        spacing: 8
        Row { spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
              Read { text: "RT " + Math.round(PadCal.trigOut(v.t, "r", v.trig[1]) * 100) + "%"; anchors.verticalCenter: parent.verticalCenter }
              UiButton { padX: 10; text: "RB"; on: v.held(311); anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 8
              PadStick { view: v; stick: 1; d: Math.round(108 * Theme.scale); rings: false }
              PadTrigger { view: v; which: 1; h: Math.round(100 * Theme.scale); anchors.verticalCenter: parent.verticalCenter } }
      }
    }
    Item {   // bottom strip (like the Stats drop): battery left, the dot legend right
      width: parent.width; height: Math.round(16 * Theme.scale)
      Row {
        visible: v.batt >= 0
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: 8
        UiCaption { text: "Battery"; anchors.verticalCenter: parent.verticalCenter }
        DotMeter { value: v.batt / 100; count: 10; anchors.verticalCenter: parent.verticalCenter }
        UiNum { text: v.batt + "%"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
        UiCaption { text: v.battState; visible: text !== ""; anchors.verticalCenter: parent.verticalCenter }
      }
      PadLegend { anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
    }
  }

  // battery: the pad's power_supply in sysfs (hid-sony / hid-playstation / xpad wireless); none (dongles, wired) = hidden
  property int batt: -1
  property string battState: ""
  Process {
    id: battRead
    command: ["sh", "-c", "d=$(ls -d /sys/class/input/" + (v.pad ? v.pad.path.split("/").pop() : "-") + "/device/device/power_supply/* 2>/dev/null | head -1); [ -n \"$d\" ] && cat \"$d/capacity\" \"$d/status\""]
    stdout: StdioCollector { onStreamFinished: { const f = this.text.trim().split("\n"); v.batt = f[0] !== "" && !isNaN(Number(f[0])) ? Number(f[0]) : -1; v.battState = f[1] === "Charging" ? "Charging" : f[1] === "Full" ? "Full" : "" } }
  }
  Timer { interval: 30000; repeat: true; triggeredOnStart: true; running: v.visible && !!v.pad; onTriggered: { battRead.running = false; battRead.running = true } }
  onPadChanged: { batt = -1; battRead.running = false; battRead.running = true }

  // ---- one stick: circle (drag the rings) + response graph (drag the curve) ----
  Row {
    visible: v.part === "l" || v.part === "r"
    anchors.centerIn: parent
    spacing: Math.round(28 * Theme.scale)
    readonly property string side: v.part === "r" ? "r" : "l"
    Column {
      spacing: 8
      PadStick { view: v;
        id: big
        stick: v.part === "r" ? 1 : 0
        d: Math.round(140 * Theme.scale)
        MouseArea {   // drag the nearer ring: deadzone or outer deadzone
          anchors.fill: parent
          cursorShape: Qt.SizeFDiagCursor
          preventStealing: true   // the settings page must not scroll away mid-drag
          property string which: ""
          function rAt(m) { return Math.hypot(m.x - big.d / 2, m.y - big.d / 2) / (big.d / 2) }
          onPressed: m => { const r = rAt(m); which = Math.abs(r - v.t[big.side + "dz"] / 100) <= Math.abs(r - (1 - v.t[big.side + "out"] / 100)) ? "dz" : "out"; onPositionChanged(m) }
          onPositionChanged: m => { if (!pressed) return; const r = rAt(m); v.preview(big.side + which, which, which === "dz" ? r * 100 : (1 - r) * 100) }
          onReleased: v.commit()
        }
      }
      PadLegend { anchors.horizontalCenter: parent.horizontalCenter }
    }
    Column {
      spacing: 8
      Item {   // response: input tilt (x) -> output tilt (y), drawn in dots
        id: graph
        readonly property real d: Math.round(140 * Theme.scale)
        readonly property real inR: Math.min(1, Math.hypot(big.inXY[0], big.inXY[1]))
        readonly property string side: big.side
        width: d; height: d
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.edge; radius: Theme.radiusInner }
        Repeater {   // linear reference: the diagonal, faint
          model: 17
          Rectangle { required property int index; width: 2; height: 2; radius: 1; color: Theme.text; opacity: 0.25
                      x: index / 16 * (graph.d - 8) + 3; y: graph.d - 5 - index / 16 * (graph.d - 8) }
        }
        Repeater {
          model: 33
          Rectangle {
            required property int index
            readonly property real ix: index / 32
            width: 4; height: 4; radius: 2; color: Theme.text; opacity: 0.55
            x: ix * (graph.d - 8) + 2; y: graph.d - 6 - PadCal.radial(v.t, graph.side, ix) * (graph.d - 8)
          }
        }
        Rectangle {   // live point
          width: 10; height: 10; radius: 5; color: Theme.accent
          x: graph.inR * (graph.d - 8) - 1; y: graph.d - 9 - PadCal.radial(v.t, graph.side, graph.inR) * (graph.d - 8)
        }
        MouseArea {   // drag up / down: the curve passes through the pointer at mid tilt
          anchors.fill: parent
          cursorShape: Qt.SizeVerCursor
          preventStealing: true   // the settings page must not scroll away mid-drag
          onPositionChanged: m => { if (!pressed) return; const y = PadCal.clamp(1 - m.y / graph.d, 0.05, 0.95); v.preview(graph.side + "curve", "curve", Math.log(y) / Math.log(0.5)) }
          onPressed: m => onPositionChanged(m)
          onReleased: v.commit()
        }
      }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
        Read { text: "In"; anchors.verticalCenter: parent.verticalCenter }
        UiNum { text: Math.round(graph.inR * 100); anchors.verticalCenter: parent.verticalCenter }
        Read { text: "→  Out"; anchors.verticalCenter: parent.verticalCenter }
        UiNum { text: Math.round(PadCal.radial(v.t, graph.side, graph.inR) * 100); color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }

  // ---- triggers (drag the marks) ----
  Row {
    visible: v.part === "t"
    anchors.centerIn: parent
    spacing: Math.round(64 * Theme.scale)
    Repeater {
      model: [["LT", 0], ["RT", 1]]
      Column {
        id: tc
        required property var modelData
        readonly property int idx: modelData[1]
        readonly property string sd: idx ? "r" : "l"
        spacing: 8
        Row {
          spacing: 10
          PadTrigger { view: v;
            id: tcolumn
            which: tc.idx; h: Math.round(130 * Theme.scale)
            MouseArea {   // drag the nearer mark: Start or Full press
              anchors { fill: parent; margins: -8 }
              cursorShape: Qt.SizeVerCursor
              preventStealing: true   // the settings page must not scroll away mid-drag
              property string which: ""
              function at(m) { return PadCal.clamp((tcolumn.h - 4 - (m.y - 8)) / (tcolumn.h - 7), 0, 1) * 100 }
              onPressed: m => { const a = at(m); which = Math.abs(a - v.t[tc.sd + "ts"]) <= Math.abs(a - v.t[tc.sd + "te"]) ? "ts" : "te"; onPositionChanged(m) }
              onPositionChanged: m => { if (pressed) v.preview(tc.sd + which, which, at(m)) }
              onReleased: v.commit()
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 4
            UiNum { text: Math.round(PadCal.trigOut(v.t, tc.sd, v.trig[tc.idx]) * 100) + "%"; color: Theme.accent; font.pixelSize: Math.round(24 * Theme.scale) }
            Read { text: "Game" }
            Item { width: 1; height: 6 }
            Read { text: "Hand " + Math.round(v.trig[tc.idx] * 100) + "%" }
            Read { text: "Start " + v.t[tc.sd + "ts"] + "% · full " + v.t[tc.sd + "te"] + "%" }
          }
        }
        Read { text: tc.modelData[0]; anchors.horizontalCenter: parent.horizontalCenter }
      }
    }
  }

  Read {   // the source is not there (service starting, pad asleep)
    visible: !src.ready
    anchors { right: parent.right; top: parent.top; margins: 4 }
    text: "No signal"; color: Theme.red
  }
}
