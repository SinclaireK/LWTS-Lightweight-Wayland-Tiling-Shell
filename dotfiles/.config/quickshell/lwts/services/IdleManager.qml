// Idle actions (replaces hypridle). Times come from Settings -> Power: idle_lock / idle_screen / idle_sleep, minutes, 0 = never.
// Wayland idle-notify honours idle inhibitors (caffeine, video playing in a browser/player), so a film never locks the screen.
// Game mode with game_idle = true ("No lock / sleep") turns all three off. niri turns monitors back on at the first input.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.core
import qs.services

Scope {
  id: root
  readonly property bool allowed: !(Session.game && Prefs.get("game_idle", true) === true)
  readonly property bool onBat: UPower.onBattery   // v5: separate timers on battery (keys idle_*_bat); desktops / AC use the plain keys
  function key(k) { return onBat ? k + "_bat" : k }
  function mins(k, d) { return Number(Prefs.get(key(k), onBat ? Math.min(d, 5) : d)) }

  IdleMonitor {
    timeout: root.mins("idle_lock", 15) * 60
    enabled: root.allowed && root.mins("idle_lock", 15) > 0
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) Lock.lock()
  }
  IdleMonitor {
    timeout: root.mins("idle_screen", 16) * 60
    enabled: root.allowed && root.mins("idle_screen", 16) > 0
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) { Lock.lock(true); Compositor.powerOffMonitors() }   // a dark screen is always a locked one; niri wakes the monitors on input
  }
  IdleMonitor {
    timeout: root.mins("idle_sleep", 90) * 60
    enabled: root.allowed && root.mins("idle_sleep", 90) > 0
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) { Lock.lock(); sleepDelay.start() }   // lock first, so the screen is already locked on resume
  }
  Timer { id: sleepDelay; interval: 1500; onTriggered: Quickshell.execDetached(["systemctl", "suspend"]) }
}
