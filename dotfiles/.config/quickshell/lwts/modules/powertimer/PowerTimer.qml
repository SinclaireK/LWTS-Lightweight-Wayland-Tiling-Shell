// Sleep / power-off in N minutes. The countdown is a transient systemd user timer (`power-timer`), so it survives
// shell restarts; the shell only asks systemd once on start and after each change (no polling).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  property string action: ""   // "", "sleep", "poweroff"
  property real until: 0       // epoch ms
  property real total: 0       // length of the running timer, ms (for the bar ring)
  readonly property real progress: on && total > 0 ? Math.max(0, Math.min(1, left * 1000 / total)) : 1   // 1 -> 0

  readonly property bool on: action !== ""
  // what the tile starts next time (the last used), remembered in settings.toml
  readonly property string nextAction: Prefs.get("powertimer_action", "sleep")
  readonly property int nextMinutes: Number(Prefs.get("powertimer_minutes", 30))
  function remember(act, minutes) { if (act) Prefs.set("powertimer_action", act); if (minutes > 0) Prefs.set("powertimer_minutes", minutes) }
  function start() { set(nextAction, nextMinutes) }
  function toggle() { if (on) set("", 0); else start() }
  function add(minutes) {   // running: push the end by `minutes` (seconds kept, the ring keeps its proportions); paused: change what is left; idle: what start() will use (5 min .. 8 h)
    if (on) { const secs = Math.max(60, left + minutes * 60); set(action, secs / 60, Math.max(secs / 60, total / 60000 + minutes)) }
    else if (paused) { pausedSec = Math.max(60, pausedSec + minutes * 60); pausedTotal = Math.max(pausedTotal + minutes, pausedSec / 60) }
    else remember("", Math.max(5, Math.min(480, nextMinutes + minutes)))
  }
  function setAction(act) { if (on) set(act, Math.max(1, left / 60), total / 60000); else if (paused) pausedAction = act; else remember(act, 0) }
  // live countdown: ticks once a second only while a timer runs
  property real now: Date.now()
  readonly property int left: on ? Math.max(0, Math.round((until - now) / 1000)) : 0   // s
  function clock(sec) { const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), x = sec % 60, p = n => String(n).padStart(2, "0");
                        return h ? h + ":" + p(m) + ":" + p(x) : m + ":" + p(x) }
  readonly property string leftText: clock(left)
  function label(act) { return act === "poweroff" ? "Power off" : "Sleep" }
  readonly property string unit: "power-timer"

  // paused: the systemd timer is stopped, the seconds left are kept here (in memory: a shell restart forgets a paused timer)
  property real pausedSec: 0
  property string pausedAction: ""
  property real pausedTotal: 0       // minutes, the length it had
  readonly property bool paused: pausedSec > 0
  function pause() { if (!on) return; const a = action, s = Math.max(1, left), tm = total / 60000; set("", 0); pausedAction = a; pausedSec = s; pausedTotal = tm }
  function resume() { if (!paused) return; const a = pausedAction, s = pausedSec, tm = pausedTotal; set(a, s / 60, tm) }
  function cancel() { set("", 0) }
  function set(act, minutes, totalMin) {   // act "" = cancel; minutes may be fractional (resume); totalMin = the full length for the ring
    pausedSec = 0
    const stop = "systemctl --user stop " + unit + ".timer " + unit + ".service 2>/dev/null; systemctl --user reset-failed " + unit + ".service 2>/dev/null; "
    if (act === "" || minutes <= 0) { run.command = ["bash", "-c", stop + "true"]; action = ""; until = 0; run.running = true; return }
    const cmd = act === "sleep" ? "sleep 1; systemctl suspend -i" : "systemctl poweroff -i"
    const tm = totalMin || minutes, secs = Math.max(1, Math.round(minutes * 60))
    run.command = ["bash", "-c", stop + "systemd-run --user --quiet --unit=" + unit + " --description='LWTS " + act + " " + tm + "' --on-active=" + secs + "s --timer-property=AccuracySec=1s bash -c '" + cmd + "'"]
    action = act; until = Date.now() + secs * 1000; now = Date.now(); total = tm * 60000
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
      const p = text.trim().split(" ")   // "<action> [<minutes>] <next, s>": the length rides in the unit description (ring after a shell restart)
      if (p.length >= 2 && (p[0] === "sleep" || p[0] === "poweroff")) {
        root.action = p[0]; root.until = Number(p[p.length - 1]); root.now = Date.now()
        root.total = p.length === 3 ? Number(p[1]) * 60000 : Math.max(root.total, root.until - root.now)
      }
      else { root.action = ""; root.until = 0 }
    } }
  }
  Timer {   // the unit fires and disappears: drop the state when the time has passed
    interval: 1000; running: root.on; repeat: true
    onTriggered: { root.now = Date.now(); if (root.now >= root.until + 2000) { root.action = ""; root.until = 0 } }
  }
}
