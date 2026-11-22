// Night light for niri: wlsunset (gamma ramp through wlr-gamma-control) while `on`. Manual on/off only here;
// the day/night schedule stays in themes/daynight.lua, which flips the state file (~/.local/state/nightlight).
// wlsunset cannot change its colour while running, so a new temperature restarts it (applied when the slider is let go).
// Dimming (nightlight_gamma) has no equivalent in wlsunset and is ignored.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Singleton {
  id: root
  property bool on: false
  readonly property int temp: Math.max(1000, Math.min(6500, Number(Prefs.get("nightlight_temp", 4000))))
  readonly property bool active: on && !(Session.game && Prefs.get("game_nightlight", true) !== false)   // Lite switches it off
  function toggle() { on = !on; file.setText(on ? "on\n" : "off\n") }   // state at once; the file is for daynight.lua and the next start

  FileView {
    id: file
    path: Quickshell.env("HOME") + "/.local/state/nightlight"
    printErrors: false
    watchChanges: true
    atomicWrites: false   // a rename would drop the inotify watch: later edits of the file (daynight.lua) would go unseen
    onFileChanged: reload()
    onLoaded: root.on = text().trim() === "on"
  }
  Process {
    id: wl
    // wlsunset refuses high == low: 1 K apart = constant colour, whatever the schedule arguments say
    // a leftover wlsunset (the shell restarted, Quickshell does not kill its children) would fight this one over the gamma ramp = flicker:
    // kill strays first, and let the new one die with the shell (pdeathsig)
    command: ["sh", "-c", "pkill -x wlsunset; exec setpriv --pdeathsig TERM wlsunset \"$@\"", "sh", "-t", String(root.temp), "-T", String(root.temp + 1), "-S", "06:00", "-s", "18:00"]
    // no `running:` binding: a restart assigns running, which would break it (the light then never went off again)
    onExited: {
      if (root.expectExit) { root.expectExit = false; return }   // our own stop / restart
      if (root.active && root.crashes < 3) { root.crashes++; relaunch.restart() }   // crashed / compositor restarted: a few tries, no loop
    }
  }
  property bool expectExit: false
  property int crashes: 0
  function startWl() { if (!wl.running) wl.running = true }
  function stopWl() { if (wl.running) { expectExit = true; wl.running = false } }
  onActiveChanged: { relaunch.stop(); restart.stop(); crashes = 0; if (active) startWl(); else stopWl() }
  onTempChanged: if (active) { stopWl(); restart.restart() }   // wlsunset cannot change colour live
  Component.onCompleted: if (active) startWl()
  Timer { id: relaunch; interval: 3000; onTriggered: if (root.active) root.startWl() }
  Timer { id: restart; interval: 250; onTriggered: if (root.active) root.startWl() }
}
