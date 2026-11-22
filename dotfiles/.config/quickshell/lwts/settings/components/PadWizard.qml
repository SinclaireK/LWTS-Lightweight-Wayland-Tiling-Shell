// Gamepad calibration wizard: takes the whole Input -> Gamepad tab while PadCal.wiz !== "" (Settings swaps the rows).
// One thing per step, Steam-style: flick each stick in 8 given directions and let it snap back (the centre = the mean of the
// return points, each averaged over 300 ms after a 300 ms snap-back; slow returns, short flicks, wrong directions and outlier returns are rejected and asked again),
// roll each stick along the edge (reach), press each trigger fully twice (travel). Review -> Save / Discard / Again.
// Pad: B = cancel, A = save on the review. Nothing is applied before Save. Data: PadSource (raw).
import QtQuick
import Quickshell.Io
import qs.core
import qs.services
import qs.widgets

Item {
  id: w
  property var pad: null
  implicitHeight: col.implicitHeight + 8

  readonly property var codes: PadCal.sticks(pad)
  readonly property var trs: PadCal.triggers(pad)
  readonly property var steps: [{ id: "flick", s: 0, title: "Left stick" }, { id: "flick", s: 1, title: "Right stick" },
                                { id: "rotate", s: 0, title: "Left stick" }, { id: "rotate", s: 1, title: "Right stick" }]
                               .concat(trs.length ? [{ id: "trig", t: 0, title: "Left trigger" }, { id: "trig", t: 1, title: "Right trigger" }] : [])
  property int si: 0
  readonly property var cur: si < steps.length ? steps[si] : ({ id: "review", title: "Result" })
  readonly property var arrows: ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
  function dirAngle(k) { return (-90 + 45 * k) * Math.PI / 180 }   // screen axes: y grows down (evdev too)

  // ---- input ----
  readonly property var raw: src.raw   // code -> value, updated in place
  property real qx: 0; property real qy: 0   // active stick, factory-normalised -1..1
  property real tv: 0                        // active trigger 0..1 of its factory range
  function fh(code) { const f = PadCal.factory(pad, code); return (f[1] - f[0]) / 2 }
  function fnorm(code, v) { const f = PadCal.factory(pad, code), h = (f[1] - f[0]) / 2; return h ? (v - (f[0] + f[1]) / 2) / h : 0 }
  PadSource {   // raw values: the service's monitor socket (layer on) or the pad itself
    id: src
    pad: w.pad
    onUpdated: w.onAxis()
    onPress: code => { if (code === 305) PadCal.wiz = ""; else if (code === 304 && w.cur.id === "review") w.save() }   // B cancel, A save
  }
  Connections {
    target: PadCal
    function onWizCmd(c) { if (c === "save") w.save(); else if (c === "again") w.restart(); else if (c === "skip") w.next() }
  }

  // ---- collected data ----
  property var pts: [new Array(8).fill(null), new Array(8).fill(null)]   // per stick: settled return point (raw x, y) per direction
  property var bins: [new Array(36).fill(0), new Array(36).fill(0)]       // per stick: reach per 10 degrees (factory units)
  readonly property real litAt: 0.8   // a sector counts as reached at 80 % of the factory travel (worn sticks fall short of 90 %)
  property int litCount: 0; property real tLit: 0
  property var lo: ({}); property var hi: ({})                          // raw extremes while rolling
  property var trig: [{ rest: -Infinity, top: -Infinity, presses: 0, down: false }, { rest: -Infinity, top: -Infinity, presses: 0, down: false }]
  property var centre: ({})   // code -> raw centre (after a stick's flick step)
  property var spread: [0, 0] // per stick, % of the half range
  function restart() {
    pts = [new Array(8).fill(null), new Array(8).fill(null)]; bins = [new Array(36).fill(0), new Array(36).fill(0)];
    lo = {}; hi = {}; centre = {}; spread = [0, 0];
    trig = [{ rest: -Infinity, restMin: Infinity, top: -Infinity, presses: 0, down: false, win: null }, { rest: -Infinity, restMin: Infinity, top: -Infinity, presses: 0, down: false, win: null }];
    litCount = 0; tLit = Date.now();
    fs = "idle"; fb = ""; si = 0; PadCal.wizStage = "run";
  }
  Component.onCompleted: restart()

  // ---- feedback ----
  property string fb: ""
  property bool fbOk: true
  property int fbN: 0
  function say(ok, text) { fbOk = ok; fb = text; fbN++; fbClear.restart() }
  Timer { id: fbClear; interval: 2600; onTriggered: w.fb = "" }

  // ---- step flow ----
  property bool pausing: false   // short pause between steps so motion does not leak into the next one
  function next() {
    if (cur.id === "flick") finishCentre(cur.s);
    litCount = 0; tLit = Date.now();
    fs = "idle"; si++; pausing = true; pause.restart();
    if (si >= steps.length) PadCal.wizStage = "review";
  }
  Timer { id: pause; interval: 700; onTriggered: w.pausing = false }
  function target(s) { const i = pts[s].findIndex(v => v === null); return i }

  // flick state machine (active stick)
  property string fs: "idle"   // idle -> out (at the edge) -> back (released, settling)
  property real tEdge: 0
  property real ang: 0
  property real midSince: 0
  property bool warned: false
  property var buf: []
  property real backSince: 0
  function onAxis() {
    const c = cur;
    if (c.s !== undefined) { qx = fnorm(codes[c.s][0], raw[codes[c.s][0]] || 0); qy = fnorm(codes[c.s][1], raw[codes[c.s][1]] || 0) }
    if (c.t !== undefined) { const k = trs[c.t], f = PadCal.factory(pad, k); tv = Math.max(0, Math.min(1, ((raw[k] || 0) - f[0]) / (f[1] - f[0]))) }
    if (pausing) return;
    const now = Date.now();
    if (c.id === "flick") flick(now);
    else if (c.id === "rotate") roll();
    else if (c.id === "trig") press();
  }
  function flick(now) {
    const m = Math.hypot(qx, qy), s = cur.s, k = target(s);
    if (k < 0) return;
    if (fs === "idle") {
      if (m > 0.92) { fs = "out"; tEdge = now; ang = Math.atan2(qy, qx); midSince = 0; warned = false }
      else if (m > 0.3) { if (!midSince) midSince = now; else if (now - midSince > 700 && !warned) { say(false, "Push it all the way to the edge"); warned = true } }
      else midSince = 0;
    } else if (fs === "out") {
      if (m > 0.92) { tEdge = now; ang = Math.atan2(qy, qx) }
      else if (m < 0.3) {
        if (now - tEdge > 160) { fs = "idle"; say(false, "Let go of it: do not guide it back"); return }
        const d = Math.abs(((ang - dirAngle(k)) % (2 * Math.PI) + 3 * Math.PI) % (2 * Math.PI) - Math.PI);
        if (d > Math.PI / 6) { fs = "idle"; say(false, "Wrong direction: flick " + arrows[k]); return }
        fs = "back"; buf = []; backSince = now;
      }
    } else if (fs === "back") {
      if (m > 0.3) { fs = "idle"; say(false, "Do not touch it while it settles"); return }
      buf.push([now, raw[codes[s][0]] || 0, raw[codes[s][1]] || 0]);
    }
  }
  Timer {   // "back": 300 ms to snap back, then the next 300 ms are averaged (sticks jitter 1-5 % at rest: no stillness test)
    interval: 40; repeat: true; running: w.cur.id === "flick" && w.fs === "back"
    onTriggered: {
      const now = Date.now(), s = w.cur.s, c = w.codes[s];
      if (now - w.backSince < 600) return;
      const b = w.buf.filter(e => e[0] >= w.backSince + 300), pts2 = b.length ? b : [[now, w.raw[c[0]] || 0, w.raw[c[1]] || 0]];
      w.accept(s, [pts2.reduce((a, e) => a + e[1], 0) / pts2.length, pts2.reduce((a, e) => a + e[2], 0) / pts2.length]);
    }
  }
  function accept(s, point) {
    const k = target(s), p2 = pts.slice(); p2[s] = p2[s].slice(); p2[s][k] = point; pts = p2; fs = "idle";
    if (target(s) >= 0) { say(true, "Good · now " + arrows[target(s)]); return }
    // all 8: drop returns far from the others (> 3x the median distance, at least 1.5 % of the half range) and ask them again
    const c = codes[s], all = pts[s], mx = all.reduce((a, q) => a + q[0], 0) / 8, my = all.reduce((a, q) => a + q[1], 0) / 8;
    const dist = all.map(q => Math.hypot((q[0] - mx) / fh(c[0]), (q[1] - my) / fh(c[1])));
    const med = dist.slice().sort((a, b) => a - b)[4], lim = Math.max(med * 3, 0.015);
    const bad = dist.map((d, i) => d > lim ? i : -1).filter(i => i >= 0);
    if (bad.length) {
      const p3 = pts.slice(); p3[s] = p3[s].map((q, i) => bad.indexOf(i) >= 0 ? null : q); pts = p3;
      say(false, "Inconsistent return: again " + bad.map(i => arrows[i]).join(" "));
      return;
    }
    say(true, cur.title + " centred"); next();
  }
  function finishCentre(s) {
    const got = pts[s].filter(q => q), c = codes[s];
    if (!got.length) return;
    const cx = got.reduce((a, q) => a + q[0], 0) / got.length, cy = got.reduce((a, q) => a + q[1], 0) / got.length;
    const ce = Object.assign({}, centre); ce[c[0]] = cx; ce[c[1]] = cy; centre = ce;
    const sp = spread.slice(); sp[s] = Math.max(...got.map(q => Math.max(Math.abs(q[0] - cx) / fh(c[0]), Math.abs(q[1] - cy) / fh(c[1])))) * 100; spread = sp;
  }
  function roll() {
    const s = cur.s, c = codes[s];
    c.forEach(k => { const v = raw[k] || 0; if (lo[k] === undefined || v < lo[k]) lo[k] = v; if (hi[k] === undefined || v > hi[k]) hi[k] = v });
    const ox = centre[c[0]] !== undefined ? fnorm(c[0], centre[c[0]]) : 0, oy = centre[c[1]] !== undefined ? fnorm(c[1], centre[c[1]]) : 0;
    const x = qx - ox, y = qy - oy, r = Math.hypot(x, y), b = Math.floor(((Math.atan2(y, x) + Math.PI) / (2 * Math.PI)) * 36) % 36;
    if (r > bins[s][b]) { const nb = bins.slice(); nb[s] = nb[s].slice(); nb[s][b] = r; bins = nb }
    const now = Date.now(), nl = bins[s].filter(v => v > litAt).length;
    if (nl > litCount) { litCount = nl; tLit = now }
    if (nl === 36) { say(true, cur.title + ": full circle done"); next() }   // all 36: a whole circle
    else if (nl >= 28 && r > 0.5 && now - tLit > 2500) { say(true, cur.title + ": worn edge accepted (" + nl + "/36)"); next() }   // worn stick: some sectors never reach the edge
  }
  // trigger rest = the lowest plateau: a stretch < 5 % held 300 ms; rest = that stretch's highest value (its jitter).
  // A trigger at rest usually sends nothing, so a timer feeds the last value too (silence = sitting still).
  function restSample(g, v) {
    const now = Date.now();
    if (tv >= 0.05 || g.down) { g.win = null; return }
    if (!g.win) g.win = { since: now, min: v, max: v };
    g.win.min = Math.min(g.win.min, v); g.win.max = Math.max(g.win.max, v);
    if (now - g.win.since > 300 && (g.rest === -Infinity || g.win.min < g.restMin || (g.win.min === g.restMin && g.win.max < g.rest))) { g.rest = g.win.max; g.restMin = g.win.min }
  }
  Timer {
    interval: 100; repeat: true; running: w.cur.id === "trig" && !w.pausing
    onTriggered: { const t = w.cur.t, k = w.trs[t], g = w.trig.slice(); g[t] = Object.assign({}, g[t]); w.restSample(g[t], w.raw[k] || 0); w.trig = g }
  }
  function press() {
    const t = cur.t, k = trs[t], v = raw[k] || 0, g = trig.slice(); g[t] = Object.assign({}, g[t]);
    restSample(g[t], v);
    if (v > g[t].top) g[t].top = v;
    if (!g[t].down && tv > 0.6) g[t].down = true;
    else if (g[t].down && tv < 0.1) { g[t].down = false; g[t].presses++; say(true, "Press " + g[t].presses + " / 2") }
    trig = g;
    if (g[t].presses >= 2) next();
  }

  // ---- result ----
  readonly property var result: {
    if (cur.id !== "review" || !pad) return [];
    const out = [];
    [0, 1].forEach(s => {
      const c = codes[s], name = s ? "Right stick" : "Left stick";
      if (centre[c[0]] === undefined) { out.push({ name, text: "Skipped: centre unchanged", ok: false }); return }
      const parts = c.map(k => {
        const f = PadCal.factory(pad, k), h = (f[1] - f[0]) / 2, off = centre[k] - (f[0] + f[1]) / 2, ce = centre[k];
        // each side keeps its OWN measured reach (a worn side no longer shrinks the other); not measured (< 70 % of travel) = the factory edge
        const rl = lo[k] !== undefined ? ce - lo[k] : 0, rh = hi[k] !== undefined ? hi[k] - ce : 0, okl = rl > h * 0.7, okh = rh > h * 0.7;
        return { k, c: ce, off: off / h * 100, min: okl ? Math.max(f[0], ce - rl * 0.97) : f[0], max: okh ? Math.min(f[1], ce + rh * 0.97) : f[1], measured: okl && okh };
      });
      const steps2 = [0, 2, 4, 6, 8, 10, 12, 15, 20, 25, 30], dz = steps2.find(v => v >= spread[s] + 1) || 30;
      out.push({ name, ok: true, parts, dz, side: s ? "r" : "l",
                 text: "Centre X " + sg(parts[0].off) + " · Y " + sg(parts[1].off) + " · return spread " + spread[s].toFixed(2) + "% · recommended deadzone " + dz + "%" + (parts[0].measured && parts[1].measured ? "" : " · edge not measured: factory edge") });
    });
    trs.forEach((k, t) => {
      const g = trig[t], f = PadCal.factory(pad, k), R = f[1] - f[0], name = t ? "Right trigger" : "Left trigger";
      const rest = g.rest === -Infinity ? f[0] : g.rest;   // never seen at rest long enough: the factory bottom
      if (g.presses < 1 || g.top - rest < R * 0.5) { out.push({ name, text: "Skipped: travel unchanged", ok: false }); return }
      out.push({ name, ok: true, k, min: rest + R * 0.01, max: g.top - R * 0.01,
                 text: "Travel " + ((rest - f[0]) / R * 100).toFixed(1) + "% – " + ((g.top - f[0]) / R * 100).toFixed(1) + "%" });
    });
    return out;
  }
  function sg(v) { return (v > 0 ? "+" : "") + v.toFixed(2) + "%" }
  function save() {
    const list = [];
    result.filter(r => r.ok).forEach(r => { if (r.parts) r.parts.forEach(q => list.push([q.k, q.min, q.max, q.c])); else list.push([r.k, r.min, r.max]) });
    const tunes = {};   // calibration never changes deadzones: it only records the recommendation (Settings -> Sticks)
    result.filter(r => r.ok && r.dz !== undefined).forEach(r => tunes[r.side + "rec"] = r.dz);
    PadCal.saveAll(pad, list, tunes);   // one write
    PadCal.wiz = "";
  }

  // ---- view ----
  component Read: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  Timer { id: blink; property bool on: true; interval: 380; repeat: true; running: true; onTriggered: on = !on }

  Column {
    id: col
    width: parent.width
    spacing: 12
    Item {   // step counter + step dots
      width: parent.width; height: 14
      UiCaption { text: w.cur.id === "review" ? "Review" : "Step " + (w.si + 1) + " / " + w.steps.length; anchors.verticalCenter: parent.verticalCenter }
      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 5
        Repeater {
          model: w.steps.length
          Rectangle { required property int index; width: 6; height: 6; radius: 3
                      color: Theme.accent; opacity: index < w.si ? 1 : index === w.si ? (blink.on ? 1 : 0.3) : 0.18 }
        }
      }
    }
    UiTitle { text: w.cur.title }
    Text {   // the one instruction
      width: parent.width; wrapMode: Text.WordWrap
      color: Theme.accent; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(15 * Theme.scale)
      text: w.pausing ? "…"
          : w.cur.id === "flick" ? (w.target(w.cur.s) >= 0 ? "Flick " + w.arrows[w.target(w.cur.s)] + " to the edge and let go" : "")
          : w.cur.id === "rotate" ? "Roll the stick slowly along the edge, full circle"
          : w.cur.id === "trig" ? "Press it all the way, then release · " + w.trig[w.cur.t].presses + " / 2"
          : "Check the result: save with A, cancel with B"
    }

    Item {   // the big picture of the active part
      visible: w.cur.id !== "review"
      width: parent.width; height: Math.round(230 * Theme.scale)
      Item {   // stick
        id: big
        visible: w.cur.s !== undefined
        readonly property real d: Math.round(200 * Theme.scale)
        width: d; height: d; anchors.centerIn: parent
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: Theme.edge }
        UiDotLine { width: big.d; anchors.verticalCenter: parent.verticalCenter }
        UiDotLine { width: big.d; anchors.centerIn: parent; rotation: 90 }
        Repeater {   // flick: 8 targets on the rim
          model: w.cur.id === "flick" ? 8 : 0
          Rectangle {
            required property int index
            readonly property bool done: w.cur.s !== undefined && w.pts[w.cur.s][index] !== null
            readonly property bool aim: w.cur.s !== undefined && w.target(w.cur.s) === index
            width: aim ? 14 : done ? 9 : 6; height: width; radius: width / 2
            color: done || aim ? Theme.accent : Theme.text
            opacity: aim ? (blink.on ? 1 : 0.25) : done ? 1 : 0.25
            x: big.d / 2 + Math.cos(w.dirAngle(index)) * (big.d / 2 + 14) - width / 2
            y: big.d / 2 + Math.sin(w.dirAngle(index)) * (big.d / 2 + 14) - height / 2
          }
        }
        Repeater {   // rotate: 36 rim dots light up when reached
          model: w.cur.id === "rotate" ? 36 : 0
          Rectangle {
            required property int index
            readonly property real a: (index + 0.5) / 36 * 2 * Math.PI - Math.PI
            readonly property bool lit: w.cur.s !== undefined && w.bins[w.cur.s][index] > w.litAt
            width: lit ? 7 : 4; height: width; radius: width / 2; color: Theme.accent; opacity: lit ? 1 : 0.2
            x: big.d / 2 + Math.cos(a) * (big.d / 2 + 12) - width / 2; y: big.d / 2 + Math.sin(a) * (big.d / 2 + 12) - height / 2
          }
        }
        Rectangle {   // live stick
          width: 12; height: 12; radius: 6; color: Theme.accent
          x: big.d / 2 + Math.max(-1, Math.min(1, w.qx)) * big.d / 2 - 6
          y: big.d / 2 + Math.max(-1, Math.min(1, w.qy)) * big.d / 2 - 6
        }
      }
      Item {   // centre x10: where the stick came back to (flick step)
        id: zoom
        visible: w.cur.id === "flick"
        readonly property real d: Math.round(96 * Theme.scale)
        readonly property real k: 10
        width: d; height: d
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: Theme.line }
        Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.dim; anchors.centerIn: parent }
        Repeater {
          model: w.cur.s !== undefined ? w.pts[w.cur.s] : []
          Rectangle {
            required property var modelData
            visible: modelData !== null
            readonly property var c: w.codes[w.cur.s] || [0, 1]
            width: 5; height: 5; radius: 2.5; color: Theme.accent
            x: zoom.d / 2 + Math.max(-1, Math.min(1, (modelData ? w.fnorm(c[0], modelData[0]) : 0) * zoom.k)) * zoom.d / 2 - 2.5
            y: zoom.d / 2 + Math.max(-1, Math.min(1, (modelData ? w.fnorm(c[1], modelData[1]) : 0) * zoom.k)) * zoom.d / 2 - 2.5
          }
        }
        Read { anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter } text: "Returns ×10" }
      }
      Column {   // trigger
        visible: w.cur.t !== undefined
        anchors.centerIn: parent
        spacing: 10
        DotMeter { value: w.tv; count: 24; dotSize: 9; gap: 4; anchors.horizontalCenter: parent.horizontalCenter }
        UiNum { text: Math.round(w.tv * 100) + "%"; font.pixelSize: Math.round(28 * Theme.scale); anchors.horizontalCenter: parent.horizontalCenter }
      }
    }

    Row {   // feedback of the last attempt
      visible: w.cur.id !== "review"
      height: 18; spacing: 8
      Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; visible: w.fb !== ""
                  color: w.fbOk ? Theme.accent : Theme.red }
      Text { anchors.verticalCenter: parent.verticalCenter; text: w.fb
             color: w.fbOk ? Theme.text : Theme.red; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(12 * Theme.scale) }
    }

    Column {   // review
      visible: w.cur.id === "review"
      width: parent.width; spacing: 8
      Repeater {
        model: w.result
        Row {
          required property var modelData
          spacing: 12
          Read { width: Math.round(110 * Theme.scale); text: modelData.name }
          Read { color: modelData.ok ? Theme.text : Theme.dim; text: modelData.text }
        }
      }
    }
  }
}
