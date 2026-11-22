// System facts for Settings: monitors with their modes (niri outputs), About (host, kernel, Quickshell).
// refresh() on opening Settings; nothing runs in the background.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  // niri output -> the shape Settings already uses (hyprctl-style transform numbers, "WxH@R.RRHz" mode strings)
  readonly property var _transform: ({ Normal: 0, "90": 1, "180": 2, "270": 3, Flipped: 4, Flipped90: 5, Flipped180: 6, Flipped270: 7 })
  function _mode(m) { return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(2) + "Hz" }
  readonly property var monitors: Object.values(Compositor.outputs).map(o => {
    const cur = o.modes[o.current_mode] || o.modes[0] || { width: 0, height: 0, refresh_rate: 0 };
    const lg = o.logical || { x: 0, y: 0, scale: 1, transform: "Normal" };
    return { name: o.name, mode: _mode(cur), modes: [...new Set(o.modes.map(_mode))], scale: lg.scale,
             x: lg.x, y: lg.y, width: cur.width, height: cur.height, vrr: o.vrr_enabled, transform: _transform[lg.transform] || 0 };
  })
  property var about: ({})
  function refresh() { Compositor.refreshOutputs(); if (!about.kernel) info.running = true }

  Process {
    id: info
    command: ["sh", "-c", "cat /etc/hostname; uname -r; qs --version | head -1 | cut -d' ' -f2; . /etc/os-release; echo \"$PRETTY_NAME\"; "
      + "grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//'; "
      + "lspci -mm | grep -i vga | awk -F'\"' '{print $6}' | head -1; "
      + "free -h --si | awk '/^Mem:/ {print $2}'; uptime -p"]
    stdout: StdioCollector {
      onStreamFinished: { const l = text.split("\n");
        root.about = { host: l[0], kernel: l[1], qs: l[2], os: l[3], cpu: l[4], gpu: l[5], ram: l[6], uptime: l[7] } }
    }
  }
}
