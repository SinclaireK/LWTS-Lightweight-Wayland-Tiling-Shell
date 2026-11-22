// Data for the Tasks window: apps grouped by process name, per-core load, disk and network rates, one sample a second from `lwts-procs`
// (luajit, reads /proc). The reader runs only while the window is shown (`shown`); nothing runs otherwise. CPU / GPU / RAM come from SysMon.
// History (last minute) is kept here per resource: cpu mem gpu (0..1), disk net (bytes/s, normalised at read time by the minute's peak).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property bool shown: false
  property string res: "cpu"    // Performance: the chosen resource (cpu, mem, disk:<dev>, net:<if>, gpu)
  property string tab: "proc"   // proc | perf: `qs -c lwts ipc call tasks open perf`
  property var cores: []     // 0..1 per core
  property var apps: []      // [{ n, c (processes), cpu (% of the whole machine), mem (MB), pids }]
  property var procs: []     // flat: [pid, name, state, cpu, mem]
  property var services: []  // [{ n, state (running/stopped/failed), sub, desc }]  - read while the Services tab is open
  property var startup: []   // [{ n, on (bool), src }]
  property var sys: ({})     // lwts-sys: load, uptime, handles, per-core clock, memory breakdown, disks[], nets[], gpu{} (while the Performance tab is open)
  property var cpuInfo: ({})  // lscpu: model, sockets, cores, threads, caches, min / max MHz
  property bool wantSys: false
  property var disk: [0, 0]  // read, write bytes/s
  property var net: [0, 0]   // down, up bytes/s
  property var hist: ({ cpu: [], mem: [], gpu: [], disk: [], net: [] })
  property int rev: 0        // +1 per sample: graphs repaint on it
  readonly property int len: 60
  readonly property var floors: ({ disk: 20e6, net: 12.5e6 })   // the smallest scale: 20 MB/s, 100 Mbit
  function toggle() { shown = !shown }
  function push2(id, v) { const h = hist; h[id] = push(h[id] || [], v) }
  function end(pids) { if (pids && pids.length) Quickshell.execDetached(["kill", "-15"].concat(pids.map(String))) }
  function series(id) {   // 0..1; byte-rate series are scaled by the minute's peak (floor 20 MB/s disk, 12.5 MB/s net)
    const a = hist[id] || [];
    const kind = id.split(":")[0];
    if (kind !== "disk" && kind !== "net" && kind !== "netRx" && kind !== "netTx") return a;
    const m = Math.max(kind === "disk" ? floors.disk : floors.net, ...(hist[kind === "netRx" || kind === "netTx" ? "net:" + id.split(":")[1] : id] || a));
    return a.map(v => v / m);
  }
  function level(id) { const a = series(id); return a.length ? a[a.length - 1] : 0 }
  onShownChanged: { SysMon.active = shown; if (!shown) hist = { cpu: [], mem: [], gpu: [], disk: [], net: [] } }
  function push(a, v) { return a.concat([v]).slice(-len) }
  Process {
    running: root.shown
    command: [Quickshell.env("HOME") + "/.local/bin/lwts-procs"]
    stdout: SplitParser { onRead: line => {
      try {
        const d = JSON.parse(line);
        root.procs = d.procs.map(a => ({ pid: a[0], n: a[1], st: a[2], cpu: a[3], mem: a[4], cpuN: Math.min(1, a[3] / 25) })); root.cores = d.cores; root.apps = d.apps.map(a => { a.cpuN = Math.min(1, a.cpu / 25); return a }); root.disk = d.disk; root.net = d.net;
        const h = root.hist;
        root.hist = { cpu: root.push(h.cpu, SysMon.cpu), mem: root.push(h.mem, SysMon.ram), gpu: root.push(h.gpu, SysMon.gpu),
                      disk: root.push(h.disk, d.disk[0] + d.disk[1]), net: root.push(h.net, d.net[0] + d.net[1]) };
        root.rev++
      } catch (e) {}
    } }
  }

  // Services (read-only): systemctl list-units, refreshed every 4 s while the tab is open
  property bool wantServices: false
  Process {
    id: svcP
    command: ["systemctl", "list-units", "--type=service", "--all", "--plain", "--no-legend", "--no-pager"]
    stdout: StdioCollector { onStreamFinished: {
      const out = [];
      for (const l of text.split("\n")) {
        const m = l.match(/^(\S+)\.service\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$/);
        if (m) out.push({ n: m[1], load: m[2], state: m[4] === "running" ? "running" : m[3] === "failed" ? "failed" : m[3] === "active" ? "active" : "stopped", sub: m[4], desc: m[5] });
      }
      root.services = out
    } }
  }
  Timer { interval: 4000; repeat: true; triggeredOnStart: true; running: root.shown && root.wantServices; onTriggered: if (!svcP.running) svcP.running = true }
  // Startup apps: autostart .desktop files (user ones shadow /etc/xdg) + the compositor's spawn-at-startup lines
  property bool wantStartup: false
  Process {
    id: startP
    command: ["sh", "-c", `
for d in "$HOME/.config/autostart" /etc/xdg/autostart; do
  for f in "$d"/*.desktop; do [ -e "$f" ] || continue
    b=$(basename "$f"); case " $seen " in *" $b "*) continue;; esac; seen="$seen $b"
    n=$(sed -n 's/^Name=//p' "$f" | head -1); [ -n "$n" ] || n=\${b%.desktop}
    on=1; grep -qiE '^(Hidden=true|X-GNOME-Autostart-enabled=false)' "$f" && on=0
    printf '%s\t%s\t%s\n' "$n" "$on" "autostart"
  done
done
grep -E '^[[:space:]]*spawn-at-startup' "$HOME/.config/niri/config.kdl" "$HOME/.config/niri/lwts.kdl" 2>/dev/null | sed -E 's#^[^:]*:[[:space:]]*spawn-at-startup[[:space:]]+##; s#"##g; s#[[:space:]]*//.*$##' | while read -r l; do printf '%s\t1\t%s\n' "$l" "niri"; done`]
    stdout: StdioCollector { onStreamFinished: {
      root.startup = text.split("\n").filter(l => l !== "").map(l => { const f = l.split("\t"); return { n: f[0], on: f[1] === "1", src: f[2] } })
    } }
  }
  onWantStartupChanged: if (wantStartup && shown) startP.running = true

  // Performance extras: one more reader while that tab is open, and the static CPU facts once
  Process {
    running: root.shown && root.wantSys
    command: [Quickshell.env("HOME") + "/.local/bin/lwts-sys"]
    stdout: SplitParser { onRead: line => {
      try {
        const d = JSON.parse(line);
        root.sys = d;
        for (const x of d.disks || []) { push2("disk:" + x.n, (x.rd || 0) + (x.wr || 0)); push2("diskA:" + x.n, (x.active || 0) / 100) }
        for (const x of d.nets || []) { push2("net:" + x.n, (x.rx || 0) + (x.tx || 0)); push2("netRx:" + x.n, x.rx || 0); push2("netTx:" + x.n, x.tx || 0) }
        const m = d.mem || {};
        if (m.swapTotal > 0) push2("swap", (m.swapTotal - m.swapFree) / m.swapTotal);
        if (d.gpu) { push2("gpuVram", d.gpu.vramTotal > 0 ? d.gpu.vram / d.gpu.vramTotal : 0); push2("gpuTemp", (d.gpu.tJunc || d.gpu.tEdge || 0) / 110); push2("gpuPow", d.gpu.cap > 0 ? d.gpu.power / d.gpu.cap : 0) }
        root.hist = root.hist
      } catch (e) {}
    } }
  }
  Process {
    running: root.shown
    command: ["lscpu", "-J"]
    stdout: StdioCollector { onStreamFinished: {
      try { const m = ({}); for (const e of JSON.parse(text).lscpu) m[e.field.replace(/:$/, "")] = e.data; root.cpuInfo = m } catch (e) {}
    } }
  }
}
