// CPU / RAM / GPU / temperature and the focused window's process. Reads /proc and /sys once a second, and only
// while the SysMon panel is open (`active`); nothing runs otherwise.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property bool active: false
  property bool barWants: false   // the bar shows live CPU / GPU / RAM (desktop): keep sampling
  property real cpu: 0; property real ram: 0; property real ramGb: 0; property real gpu: 0
  property int cpuTemp: 0; property int gpuTemp: 0
  property real swapGb: 0; property real swapTotal: 0; property real gpuW: 0; property real cpuGhz: 0; property real vramUsed: 0; property real vramTotal: 0   // GHz, GB
  property var histCpu: []; property var histGpu: []   // last HIST samples, one per tick (the Stats panel graph)
  readonly property int hist: 60
  function pushHist() {
    histCpu = histCpu.concat([cpu]).slice(-hist); histGpu = histGpu.concat([gpu]).slice(-hist)
  }
  readonly property var live: Compositor.focusedWindow ? { title: Compositor.focusedWindow.title, cls: Compositor.focusedWindow.app_id, pid: Compositor.focusedWindow.pid } : ({})
  // the panel takes keyboard focus on click, so `live` goes empty: keep the last real window while the panel is open
  property var win: ({})
  onLiveChanged: if (live.pid) win = live
  onActiveChanged: if (active) win = live
  property var last: null

  function kill() { if (win.pid) Quickshell.execDetached(["kill", "-15", String(win.pid)]) }

  Timer { interval: 1000; running: root.active || root.barWants; repeat: true; triggeredOnStart: true; onTriggered: { root.pushHist(); stat.reload(); mem.reload(); gpuF.reload(); ct.reload(); gt.reload(); mhz.reload(); gw.reload(); vu.reload(); vt.reload() } }

  FileView { id: stat; path: "/proc/stat"
    onLoaded: { const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number), idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
                if (root.last) root.cpu = 1 - (idle - root.last[0]) / Math.max(1, total - root.last[1]); root.last = [idle, total] } }
  FileView { id: mem; path: "/proc/meminfo"
    onLoaded: { const g = k => Number((text().match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]); const t = g("MemTotal"), a = g("MemAvailable");
                root.ram = 1 - a / t; root.ramGb = (t - a) / 1048576; const st = g("SwapTotal"), sf = g("SwapFree"); root.swapTotal = st / 1048576; root.swapGb = (st - sf) / 1048576 } }
  // hwmon / card numbers move between boots: find the sensors by name once at start
  FileView { id: gpuF; onLoaded: root.gpu = Number(text()) / 100 }
  FileView { id: mhz; path: "/proc/cpuinfo"
    onLoaded: { const m = text().match(/cpu MHz\s*:\s*([\d.]+)/g) || []; if (m.length) root.cpuGhz = m.reduce((a, x) => a + Number(x.split(":")[1]), 0) / m.length / 1000 } }
  FileView { id: gw; onLoaded: root.gpuW = Number(text()) / 1e6 }   // amdgpu power1_average, µW
  FileView { id: vu; onLoaded: root.vramUsed = Number(text()) / 1073741824 }
  FileView { id: vt; onLoaded: root.vramTotal = Number(text()) / 1073741824 }
  FileView { id: ct; onLoaded: root.cpuTemp = Math.round(Number(text()) / 1000) }
  FileView { id: gt; onLoaded: root.gpuTemp = Math.round(Number(text()) / 1000) }
  Process {
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in k10temp|coretemp) echo cpu $h/temp1_input;; amdgpu) echo gput $h/temp1_input; echo gpub $(readlink -f $h/device)/gpu_busy_percent;; esac; done"]
    stdout: StdioCollector { onStreamFinished: { for (const l of text.split("\n")) { const [k, v] = l.split(" ");
      if (k === "cpu") ct.path = v; else if (k === "gput") { gt.path = v; gw.path = v.replace("temp1_input", "power1_average") } else if (k === "gpub") { gpuF.path = v; const d = v.substring(0, v.lastIndexOf("/")); vu.path = d + "/mem_info_vram_used"; vt.path = d + "/mem_info_vram_total" } } } }
  }
}
