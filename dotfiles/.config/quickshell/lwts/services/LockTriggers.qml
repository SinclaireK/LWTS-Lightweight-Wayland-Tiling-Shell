// When the screen must be locked without anyone asking: (1) the session start (greetd autologin has no password), (2) every suspend,
// whoever asked for it (power menu, lid, systemctl, idle). Screen-off lock lives in IdleManager. Resume needs nothing: the lock is already up.
// Boot: a marker in $XDG_RUNTIME_DIR (wiped at logout / reboot) tells a fresh session from a shell restart (`lwts restart` must not lock).
// Sleep: a logind "delay" inhibitor is held while awake; on PrepareForSleep(true) the lock is raised, then the inhibitor is released so
// the machine really sleeps only after the lock surface exists (max 5 s, InhibitDelayMaxSec). A new one is taken after resume.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Scope {
  id: root
  property bool sleeping: false

  // ---- session start
  Process {
    id: boot
    running: true
    command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/lwts-session-locked\"; if [ -e \"$f\" ]; then echo no; else : > \"$f\"; echo yes; fi"]
    stdout: StdioCollector { onStreamFinished: if (text.trim() === "yes" && Prefs.get("lock_on_start", true) !== false) bootDelay.start() }
  }
  Timer { id: bootDelay; interval: 800; onTriggered: Lock.lock(true) }   // let the screens appear first

  // ---- sleep
  Process {
    id: inhibitor
    running: true
    command: ["systemd-inhibit", "--what=sleep", "--who=LWTS", "--why=Lock the screen before sleep", "--mode=delay", "sleep", "infinity"]
  }
  Process {
    id: watch
    running: true
    command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
    stdout: SplitParser {
      onRead: line => {
        if (line.indexOf("PrepareForSleep") < 0) return
        if (line.indexOf("(true") >= 0) {
          root.sleeping = true
          if (Prefs.get("lock_on_sleep", true) !== false) Lock.lock(true)
          release.start()
        } else if (line.indexOf("(false") >= 0) {
          root.sleeping = false
          release.stop(); inhibitor.running = true
        }
      }
    }
  }
  // let go once the lock really engaged (or after 3 s: never block suspend on a failed lock)
  Timer { id: release; interval: 3000; onTriggered: inhibitor.running = false }
  Connections { target: Lock; function onLockedChanged() { if (Lock.locked && root.sleeping) { release.stop(); inhibitor.running = false } } }
}
