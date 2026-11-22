// Sleep / power-off in N minutes. The countdown is a transient systemd user timer (`power-timer`), so it survives
// shell restarts; the shell only asks systemd once on start and after each change (no polling).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property string action: ""   // "", "sleep", "poweroff"
  property real until: 0       // epoch ms

  readonly property bool on: action !== ""
  readonly property string unit: "power-timer"

  function set(act, minutes) {   // act "" = cancel
    const stop = "systemctl --user stop " + unit + ".timer " + unit + ".service 2>/dev/null; systemctl --user reset-failed " + unit + ".service 2>/dev/null; "
    if (act === "" || minutes <= 0) { run.command = ["bash", "-c", stop + "true"]; action = ""; until = 0; run.running = true; return }
    const cmd = act === "sleep" ? "sleep 1; systemctl suspend -i" : "systemctl poweroff -i"
    run.command = ["bash", "-c", stop + "systemd-run --user --quiet --unit=" + unit + " --description='LWTS " + act + "' --on-active=" + minutes + "m --timer-property=AccuracySec=1s bash -c '" + cmd + "'"]
    action = act; until = Date.now() + minutes * 60000
    run.running = true
  }
  function refresh() { q.running = true }

  Process { id: run }
  Process {
    id: q
    command: ["bash", "-c", "systemctl --user -q is-active " + root.unit + ".timer || exit 0; " +
              "d=$(systemctl --user show " + root.unit + ".service -p Description --value 2>/dev/null); " +
              "n=$(systemctl --user list-timers " + root.unit + ".timer --no-legend -o json | grep -oE '\"next\":[0-9]+' | grep -oE '[0-9]+$'); " +
              "echo \"${d#LWTS } $((n / 1000))\""]
    stdout: StdioCollector { onStreamFinished: {
      const p = text.trim().split(" ")
      if (p.length === 2 && (p[0] === "sleep" || p[0] === "poweroff")) { root.action = p[0]; root.until = Number(p[1]) }
      else { root.action = ""; root.until = 0 }
    } }
  }
  Timer {   // the unit fires and disappears: drop the state when the time has passed
    interval: 1000; running: root.on; repeat: true
    onTriggered: if (Date.now() >= root.until + 2000) { root.action = ""; root.until = 0 }
  }
}
