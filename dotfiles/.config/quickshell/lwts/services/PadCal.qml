// Gamepads: discovery, per-pad calibration + tuning in settings.toml, and the layer switch.
// The work is done by the system service lwts-padd (/usr/local/bin/lwts-padd, root; source ~/.local/bin/lwts-padd):
// while $XDG_RUNTIME_DIR/lwts-padlayer exists it takes the physical pads away from every user process
// (72-lwts-padlayer.rules + ACL clear) and gives games a virtual Xbox 360 pad with this calibration / tuning applied,
// re-reading settings.toml on every save. Raw values of a held pad: its monitor socket (settings/components/PadSource.qml).
// `lwts-pad list` merges what the user can open with the service state (/run/lwts-pad/state):
//   pad <path> <vid:pid> <name> · range <path> <code> <min> <max> · layer on|off · virt <phys> <virt> · mon <phys> <socket>
// Keys (per vid:pid): pad_cal_<vid>_<pid> = "code:fmin:fmax:min:max[:centre],..." (f* = factory range; min/max = the measured
// edges of the stick, centre = its rest point, each side scales by its own reach; no centre = the middle; triggers: the travel),
// pad_tune_<vid>_<pid> = "name:value,..." (see tuneDefaults), pad_btn_<vid>_<pid> = "physicalKey:gameKey,..." (rebinding),
// pad_name_<vid>_<pid> = the user's name for the pad. Layer off = games read the pad as is.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  property var pads: []           // [{ path, id, name, ranges: { code: [min, max] } }]
  function start() {}             // referenced from shell.qml so the singleton (and the monitor) runs from the start

  // ---- layer ----
  readonly property bool layer: Prefs.get("pad_layer", false)
  property bool layerLive: false  // the service reports the layer as on
  property var virtOf: ({})       // physical path -> virtual pad path
  property var monOf: ({})        // physical path -> monitor socket (raw values)
  property string activePath: ""  // pad_mode "one": the pad that drives the shared virtual pad now
  // several pads: "one" = one virtual pad following the pad used last (default), "all" = one each, slots by pad_order
  readonly property string mode: Prefs.get("pad_mode", "one") === "all" ? "all" : "one"
  function order() { return String(Prefs.get("pad_order", "")).split(",").filter(x => x !== "") }
  function rank(p) { const i = order().indexOf(p.id); return i < 0 ? 99 : i }
  function makeFirst(p) { Prefs.set("pad_order", [p.id].concat(order().filter(x => x !== p.id), pads.map(q => q.id).filter(x => x !== p.id && order().indexOf(x) < 0)).join(",")) }
  readonly property bool layerRun: layer && layerLive
  onLayerChanged: flag("lwts-padlayer", layer)
  function flag(name, on) { if (Prefs.ready) Quickshell.execDetached(["sh", "-c", (on ? "touch" : "rm -f") + " \"$XDG_RUNTIME_DIR/" + name + "\""]) }

  // ---- calibration wizard (settings/components/PadWizard.qml): wiz != "" = the Gamepad tab shows only the wizard ----
  property string wiz: ""
  property string wizStage: ""    // "run" | "review"
  signal wizCmd(string c)         // "save" | "again" | "skip" from the Settings buttons

  // ---- layout: left = ABS_X/Y; right = ABS_RX/RY (xpad, hid-playstation, hid-nintendo) or ABS_Z/RZ (generic DInput) ----
  function sticks(p) { const r = p ? p.ranges : {}; return [[0, 1], r[3] && r[4] ? [3, 4] : [2, 5]] }
  function triggers(p) {   // [LT, RT]: ABS_Z/RZ when the right stick is RX/RY, else ABS_BRAKE/GAS; [] if none
    const r = p ? p.ranges : {};
    return sticks(p)[1][0] === 3 && r[2] && r[5] ? [2, 5] : r[10] && r[9] ? [10, 9] : [];
  }

  // ---- stored values ----
  // tuning (%): ldz/rdz inner deadzone, lout/rout outer deadzone, lcurve/rcurve response exponent, lad/rad anti-deadzone,
  // lts/rts trigger start, lte/rte trigger full press, jit jitter filter (kernel fuzz: noisy sticks flooded Proton with
  // 976 reports/s idle = 1-2 s lag), lrec/rrec deadzone recommended by the last calibration (info only)
  readonly property var tuneDefaults: ({ ldz: 0, rdz: 0, lout: 0, rout: 0, lcurve: 1, rcurve: 1, lad: 0, rad: 0,
                                         lts: 0, rts: 0, lte: 100, rte: 100, jit: 1.5, lrec: 0, rrec: 0 })
  function key(id) { return "pad_cal_" + String(id).replace(":", "_") }
  function tkey(id) { return "pad_tune_" + String(id).replace(":", "_") }
  function cal(id) {   // code -> { fmin, fmax, min, max }
    const out = {};
    String(Prefs.get(key(id), "")).split(",").forEach(e => { const f = e.split(":").map(Number); if ((f.length === 5 || f.length === 6) && f.every(n => !isNaN(n))) out[f[0]] = { fmin: f[1], fmax: f[2], min: f[3], max: f[4], c: f.length === 6 ? f[5] : (f[3] + f[4]) / 2 } });
    return out;
  }
  function tune(id) {
    const out = Object.assign({}, tuneDefaults);
    String(Prefs.get(tkey(id), "")).split(",").forEach(e => { const f = e.split(":"); if (f.length === 2 && out[f[0]] !== undefined && !isNaN(Number(f[1]))) out[f[0]] = Number(f[1]) });
    return out;
  }
  function factory(p, code) {   // the pad's own range: the saved one, or the reported one
    const c = cal(p.id)[code];
    return c ? [c.fmin, c.fmax] : (p.ranges[code] || [-32768, 32767]);
  }
  function offset(p, code) {   // centre shift in % of the half range (0 = factory)
    const c = cal(p.id)[code]; if (!c) return 0;
    const half = (c.fmax - c.fmin) / 2;
    return half ? (c.c - (c.fmin + c.fmax) / 2) / half * 100 : 0;
  }

  // ---- the processing, same as lwts-padd (keep both in step): previews show exactly what games get ----
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v }
  function base(p, code) { const c = cal(p.id)[code]; return c ? [c.min, c.max] : factory(p, code) }   // the edges
  function stickIn(p, i, raw) {   // stick i (0 left, 1 right) around its calibrated centre, -1..1 per axis; each side scales by its own reach
    const cc = cal(p.id);
    return sticks(p)[i].map(k => {
      const c = cc[k], f = factory(p, k), mn = c ? c.min : f[0], mx = c ? c.max : f[1], m = c ? c.c : (f[0] + f[1]) / 2;
      const d = (raw[k] !== undefined ? raw[k] : m) - m, h = d >= 0 ? mx - m : m - mn;
      return h > 0 ? d / h : 0;
    });
  }
  function radial(t, side, r) {   // input tilt 0..1+ -> output tilt 0..1: deadzone, outer deadzone, curve, anti-deadzone
    const dz = t[side + "dz"] / 100, out = t[side + "out"] / 100;
    if (r <= dz) return 0;
    const rr = Math.pow(clamp((r - dz) / Math.max(0.01, 1 - dz - out), 0, 1), Math.max(0.2, t[side + "curve"])), ad = t[side + "ad"] / 100;
    return ad + (1 - ad) * rr;
  }
  function stickOut(t, side, xy) { const r = Math.hypot(xy[0], xy[1]), o = radial(t, side, r); return r ? [clamp(xy[0] * o / r, -1, 1), clamp(xy[1] * o / r, -1, 1)] : [0, 0] }
  function trigIn(p, i, raw) {   // trigger i (0 LT, 1 RT) on its calibrated travel, 0..1
    const k = triggers(p)[i]; if (k === undefined) return 0;
    const b = base(p, k); return b[1] > b[0] ? clamp(((raw[k] !== undefined ? raw[k] : b[0]) - b[0]) / (b[1] - b[0]), 0, 1) : 0;
  }
  function trigOut(t, side, v) { const s = t[side + "ts"] / 100, e = Math.max(t[side + "te"], t[side + "ts"] + 1) / 100; return clamp((v - s) / (e - s), 0, 1) }

  // ---- writes: ONE Prefs write per change (two Prefs.set() in one tick re-read a stale file: the second undoes the first) ----
  function commit(p, c, t) {
    const o = {};
    if (c) o[key(p.id)] = Object.keys(c).map(k => [k, c[k].fmin, c[k].fmax, Math.round(c[k].min), Math.round(c[k].max), Math.round(c[k].c)].join(":")).join(",");
    if (t) o[tkey(p.id)] = Object.keys(t).filter(k => t[k] !== tuneDefaults[k]).map(k => k + ":" + t[k]).join(",");
    Prefs.setMany(o);
  }
  function withBase(p, c) {   // every stick / trigger axis keeps its factory range on record
    sticks(p)[0].concat(sticks(p)[1], triggers(p)).forEach(k => { if (!c[k]) { const f = factory(p, k); c[k] = { fmin: f[0], fmax: f[1], min: f[0], max: f[1], c: (f[0] + f[1]) / 2 } } });
    return c;
  }
  function setTune(p, name, v) { const o = {}; o[name] = v; setTunes(p, o) }
  function setTunes(p, obj) { const t = tune(p.id); for (const n in obj) t[n] = obj[n]; commit(p, null, t) }
  function saveAll(p, list, tunes) {   // wizard: [[code, min, max, centre?]] + { tune: value } in one write
    const c = withBase(p, cal(p.id)), t = tune(p.id);
    list.forEach(e => { const f = factory(p, e[0]); c[e[0]] = { fmin: f[0], fmax: f[1], min: e[1], max: e[2], c: e[3] !== undefined ? e[3] : (e[1] + e[2]) / 2 } });
    for (const n in tunes) t[n] = tunes[n];
    commit(p, c, t);
  }
  function nudge(p, code, steps) {   // manual centre: one step = 0.25 % of the half range; + moves the reading up
    const c = cal(p.id)[code], f = factory(p, code), d = -steps * (f[1] - f[0]) / 2 * 0.0025;
    saveAll(p, [[code, c ? c.min : f[0], c ? c.max : f[1], (c ? c.c : (f[0] + f[1]) / 2) + d]], {});   // only the centre moves; the edges stay
  }
  function reset(p) {   // calibration back to factory; tuning stays
    const c = cal(p.id);
    Object.keys(c).forEach(k => c[k] = { fmin: c[k].fmin, fmax: c[k].fmax, min: c[k].fmin, max: c[k].fmax, c: (c[k].fmin + c[k].fmax) / 2 });
    commit(p, c, null);
  }

  // ---- names and button rebinding (per model: vid:pid) ----
  function skey(kind, id) { return "pad_" + kind + "_" + String(id).replace(":", "_") }
  function padName(p) { const n = String(Prefs.get(skey("name", p.id), "")); return n !== "" ? n : p.name }
  function setPadName(p, n) { Prefs.set(skey("name", p.id), String(n).replace(/["\\\n]/g, "").slice(0, 40)) }
  // buttons: physical key code -> the key the game sees. DualShock 3: hid-sony reports Triangle as BTN_NORTH (0x133 = Xbox X),
  // so on the virtual Xbox pad X and Y sit swapped; the default for 054c:0268 is the swap below until the user sets his own map.
  readonly property var btnDefaults: ({ "054c:0268": "307:308,308:307" })
  function btnMap(id) {
    const out = {}, raw = Prefs.get(skey("btn", id), null);
    String(raw !== null && raw !== undefined ? raw : (btnDefaults[id] || "")).split(",").forEach(e => { const f = e.split(":").map(Number); if (f.length === 2 && f.every(n => !isNaN(n))) out[f[0]] = f[1] });
    return out;
  }
  function setBtnMap(p, m) { Prefs.set(skey("btn", p.id), Object.keys(m).filter(k => Number(k) !== m[k]).map(k => k + ":" + m[k]).join(",") || "-") }   // "-" = deliberately identity
  function rebind(p, physical, target) {   // physical button -> target; keeps the map a permutation (the old holder of target gets physical's old role)
    const m = btnMap(p.id), cur = Object.assign({}, m), keys = Object.keys(m).map(Number);
    const had = k => m[k] !== undefined ? m[k] : k;
    const old = had(physical), other = keys.concat([physical, target]).find(k => k !== physical && had(k) === target);
    cur[physical] = target;
    if (other !== undefined) cur[other] = old;
    setBtnMap(p, cur);
  }

  function swapXY(p) {   // toggle: X and Y exchanged on the game side
    const m = btnMap(p.id);
    if (m[307] === 308 && m[308] === 307) { delete m[307]; delete m[308] } else { m[307] = 308; m[308] = 307 }
    setBtnMap(p, m);
  }

  // ---- discovery ----
  Process {
    id: scan
    command: ["lwts-pad", "list"]
    stdout: StdioCollector { onStreamFinished: {
      const list = [], byPath = {}, virt = {}, mon = {}; let live = false, act = "";
      this.text.split("\n").forEach(l => {
        const f = l.split(" ");
        if (f[0] === "layer") live = f[1] === "on";
        else if (f[0] === "active") act = f[1];
        else if (f[0] === "virt") virt[f[1]] = f[2];
        else if (f[0] === "mon") mon[f[1]] = f[2];
        else if (f[0] === "pad" && !byPath[f[1]]) { const p = { path: f[1], id: f[2], name: f.slice(3).join(" "), ranges: {} }; list.push(p); byPath[p.path] = p }
        else if (f[0] === "range" && byPath[f[1]]) byPath[f[1]].ranges[Number(f[2])] = [Number(f[3]), Number(f[4])];
      });
      root.layerLive = live; root.activePath = act;
      list.sort((a, b) => root.rank(a) - root.rank(b));   // the tab lists pads in priority order
      if (JSON.stringify(virt) !== JSON.stringify(root.virtOf)) root.virtOf = virt;
      if (JSON.stringify(mon) !== JSON.stringify(root.monOf)) root.monOf = mon;
      if (JSON.stringify(list) !== JSON.stringify(root.pads)) root.pads = list;
    } }
  }
  function rescan() { scan.running = false; scan.running = true }
  Timer { id: settle; interval: 400; onTriggered: root.rescan() }   // udev sends a burst per pad
  Process {   // add / remove of any input node (pads, the service's virtual / raw pads) -> rescan; no polling
    running: true
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=input"]
    stdout: SplitParser { onRead: l => { if (/ (add|remove|change) .*\/event\d+ /.test(l + " ")) settle.restart() } }
  }
  Connections { target: Prefs; function onReadyChanged() { if (Prefs.ready) { root.flag("lwts-padlayer", root.layer); root.rescan() } } }
  Component.onCompleted: rescan()
}
