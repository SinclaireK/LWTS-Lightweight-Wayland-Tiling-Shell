// Screen backlight (laptop): brightnessctl through logind, no `video` group needed. No backlight (desktop) = available false.
// Every change goes through here (Quick settings bar, `qs -c lwts ipc call brightness up|down`), so no polling.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  property string device: ""
  property real value: 0          // 0..1
  readonly property bool available: device !== ""
  readonly property real floor: 0.01   // 0% is a black screen on most panels

  function set(v) {
    if (!available) return;
    value = Math.max(floor, Math.min(1, v));
    pending = true; if (!apply.running) apply.start();
    OsdState.brightness = value; OsdState.pop("brightness");
  }
  function step(d) { set(Math.round((value + d) * 20) / 20) }
  function refresh() { if (available) read.running = true }

  property bool pending: false
  Timer {   // a slider drag fires many moves: one brightnessctl per 40 ms
    id: apply; interval: 40
    onTriggered: { root.pending = false; Quickshell.execDetached(["brightnessctl", "-q", "-d", root.device, "set", Math.round(root.value * 100) + "%"]) }
  }
  Process {   // brightnessctl -m: name,class,current,percent%,max
    id: read
    running: true
    command: ["brightnessctl", "-m", "-c", "backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.trim().split("\n")[0].split(","), p = parseInt(f[3] || "");
        if (f[0] && !isNaN(p)) { root.device = f[0]; if (!root.pending) root.value = p / 100 }
      }
    }
  }
}
