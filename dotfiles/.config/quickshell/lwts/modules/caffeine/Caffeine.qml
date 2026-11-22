// Caffeine (settings_spec 2.7): indefinite or a timer preset; "dark screen only" swaps the Wayland idle-inhibit
// (blocks screen-off too, in Service.qml) for a systemd sleep-only inhibitor, so the display still times out normally.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  property bool on: false
  readonly property bool darkOnly: Prefs.get("caffeine_dark_only", false)
  property real until: 0   // epoch ms, 0 = indefinite
  function set(minutes) {   // 0 = indefinite, -1 = off, >0 = minutes from now
    if (minutes < 0) { on = false; until = 0; return }
    on = true; until = minutes > 0 ? Date.now() + minutes * 60000 : 0;
  }
  Timer {
    interval: 1000; running: root.on && root.until > 0; repeat: true
    onTriggered: if (Date.now() >= root.until) { root.on = false; root.until = 0 }
  }
  Process {   // only for "dark screen only": the Wayland IdleInhibitor in Service.qml blocks screen-off too
    command: ["systemd-inhibit", "--what=sleep", "--who=LWTS Caffeine", "--why=Dark screen only", "sleep", "infinity"]
    running: root.on && root.darkOnly
  }
}
