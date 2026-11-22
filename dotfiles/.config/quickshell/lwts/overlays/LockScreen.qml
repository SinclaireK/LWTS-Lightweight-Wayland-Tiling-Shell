// Lock screen: one surface per monitor (blurred wallpaper, clock, password). Password check = PAM (service "login").
// Only the surface on the focused monitor takes keys; typing on any surface works because the lock gives them keyboard focus.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.core
import qs.services

Scope {
  id: root
  // Test hook (nested compositor, no real password): LWTS_LOCK_PAM=<service> LWTS_LOCK_PAM_DIR=<dir with that PAM file>
  readonly property string pamService: Quickshell.env("LWTS_LOCK_PAM") || "login"
  readonly property string pamDir: Quickshell.env("LWTS_LOCK_PAM_DIR") || "/etc/pam.d"

  property string error: ""
  property bool busy: false

  PamContext {
    id: pam
    config: root.pamService
    configDirectory: root.pamDir
    user: Quickshell.env("USER")
    onResponseRequiredChanged: if (responseRequired && root.pending !== "") { respond(root.pending); root.pending = "" }
    onCompleted: result => {
      root.busy = false;
      if (result === PamResult.Success) { root.error = ""; root.filling = true; fillTimer.restart()}   // the dots fill up, then the plate folds
      else { root.error = result === PamResult.MaxTries ? "Too many attempts" : "Wrong password"; root.shake++ }
    }
    onError: err => { root.busy = false; root.error = "Authentication error" }
  }
  property string pending: ""
  property string typed: ""
  property bool filling: false   // the right password: the dot track fills (LockContent.success), then `leaving`
  Timer { id: fillTimer; interval: Motion.off ? 0 : Math.round(260 * Lock.anim * Motion.slowmo) + 60; onTriggered: { root.leaving = true; Lock.veil = Prefs.get("lock_veil", true) !== false; leaveTimer.restart() } }
  property bool leaving: false   // the plate folds back into the bar, then the session unlocks
  // the monitor with the bar (same pick as bar/Bar.qml)
  readonly property string mainName: ((Quickshell.screens.find(s => s.name === Prefs.get("primary_monitor", "")) || Quickshell.screens.find(s => s.name === "DP-2" || s.name === "eDP-1") || Quickshell.screens[0]) || ({ name: "" })).name
  Timer { id: leaveTimer; interval: Motion.off ? 0 : Math.round(140 * Lock.anim * Motion.slowmo); onTriggered: { root.leaving = false; Lock.unlocked() } }
  property int shake: 0
  // every lock starts clean, every unlock ends clean: `locked` may not flip back in time when the lock is called again at once, which left
  // `filling` set (new lock born "Unlocked", no timer left to finish it)
  function resetState() { fillTimer.stop(); leaveTimer.stop(); filling = false; leaving = false; busy = false; error = ""; pending = ""; typed = "" }
  Connections { target: Lock; function onWantChanged() { root.resetState() } }
  // a lock that engages again right after an unlock must start clean (a stale `filling` showed "Unlocked" and disabled the field)
  Connections { target: Lock; function onWantChanged() { if (Lock.want) { fillTimer.stop(); leaveTimer.stop(); root.filling = false; root.leaving = false; root.error = ""; root.pending = ""; root.typed = "" } } }
  function submit(pw) {
    if (busy || pw === "") return;
    busy = true; error = ""; pending = pw;
    pam.abort();
    pam.start();   // the first PAM prompt ("Password:") makes responseRequired true -> the handler above answers
  }

  WlSessionLock {
    id: lock
    locked: Lock.want
    onLockedChanged: { Lock.locked = locked; if (!locked) { root.error = ""; root.pending = ""; root.typed = ""; root.leaving = false; root.filling = false; } }

    WlSessionLockSurface {
      id: surf
      color: Theme.surface
      readonly property bool main: !!screen && screen.name === root.mainName

      LockStage {   // the plate grows out of the bar; the lock itself is drawn on the main monitor only
        id: stage
        anchors.fill: parent
        driven: true   // follows the same opening progress as the overlay (Lock.openK / openF)
        opened: true
        screenName: surf.screen ? surf.screen.name : ""
        plain: !surf.main
        Timer { interval: 1; running: !root.leaving; onTriggered: stage.afterFrames(2, () => { Lock.startOpening(); Lock.surfaceReady() }) }   // once this surface really drew, the overlay can go
        hideContent: root.leaving   // the overlay already shows the same clock and player
        LockContent {
          id: lc
          anchors.fill: parent
          ui: surf.main
          success: root.filling
          error: root.error; busy: root.busy; shake: root.shake
          onSubmit: pw => root.submit(pw)
          onTypedChanged: if (root.typed !== typed) root.typed = typed   // every monitor listens, any of them may get the keys
          Connections { target: root; function onTypedChanged() { if (lc.typed !== root.typed) lc.typed = root.typed } }
        }
      }
    }
  }
}
