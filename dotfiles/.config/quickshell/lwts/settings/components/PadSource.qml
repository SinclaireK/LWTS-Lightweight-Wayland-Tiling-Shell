// Raw values of one physical pad for the Gamepad tab (live view, calibration wizard), in the `lwts-pad watch` format.
// Layer on: the lwts-padd monitor socket (users cannot open the pad itself); layer off: `lwts-pad watch <pad>`.
// `raw` (code -> value) and `keys` (code -> held) are updated in place; `updated()` fires per line, `press(code)` on a key down.
import QtQuick
import Quickshell.Io
import qs.services

Item {
  id: s
  property var pad: null
  property bool active: true
  property var raw: ({})
  property var keys: ({})
  property bool ready: false
  signal updated()
  signal press(int code)
  readonly property string mon: pad && PadCal.layerRun ? (PadCal.monOf[pad.path] || "") : ""
  function parse(line) {
    const f = line.split(" ");
    if (f[0] === "a") { raw[f[1]] = Number(f[2]); updated() }
    else if (f[0] === "k") { keys[f[1]] = f[2] !== "0"; if (f[2] === "1") press(Number(f[1])); updated() }
    else if (f[0] === "abs") raw[f[1]] = Number(f[6])
    else if (f[0] === "ready") { ready = true; updated() }
    else if (f[0] === "gone") ready = false
  }
  Socket {
    path: s.mon
    connected: s.active && s.mon !== ""
    parser: SplitParser { onRead: l => s.parse(l) }
    onConnectionStateChanged: if (!connected) s.ready = false
  }
  Process {
    running: s.active && !!s.pad && !PadCal.layerRun
    command: ["lwts-pad", "watch", s.pad ? s.pad.path : ""]
    stdout: SplitParser { onRead: l => s.parse(l) }
  }
}
