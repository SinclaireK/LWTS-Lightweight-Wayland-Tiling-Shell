// Launcher tools (round 8): colour picker (grim + slurp, no extra package), text from a screen area (tesseract, optional),
// stopwatch, countdown timer. Picker / OCR close the launcher first (slurp needs the screen).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Singleton {
  id: root
  property string color: Prefs.get("tools_last_color", "")
  property string ocrState: ""            // "" | "busy" | "copied" | "empty" | "missing"
  property bool hasOcr: false
  Process { running: true; command: ["sh", "-c", "command -v tesseract"]; onExited: code => root.hasOcr = code === 0 }

  function closeLauncher() { const l = Modules.ctx && Modules.ctx.launcher; if (l) l.close() }
  function pick() { closeLauncher(); pickDelay.restart() }
  Timer { id: pickDelay; interval: 350; onTriggered: picker.running = true }
  Process {
    id: picker
    command: ["sh", "-c", 'g=$(slurp -p) || exit 1; grim -g "$g" -t ppm - | tail -c 3 | od -An -tx1 | tr -d " \\n"']
    stdout: StdioCollector { onStreamFinished: { const h = text.trim(); if (/^[0-9a-f]{6}$/.test(h)) { root.color = "#" + h.toUpperCase(); Prefs.set("tools_last_color", root.color); Quickshell.execDetached(["wl-copy", root.color]) } } }
  }
  function ocr() { if (!hasOcr) { ocrState = "missing"; return } closeLauncher(); ocrDelay.restart() }
  Timer { id: ocrDelay; interval: 350; onTriggered: { root.ocrState = "busy"; ocrProc.running = true } }
  Process {
    id: ocrProc
    command: ["sh", "-c", 'g=$(slurp) || exit 1; t=$(grim -g "$g" -t png - | tesseract - - -l "$(tesseract --list-langs 2>/dev/null | grep -xE "ukr|rus|eng" | paste -sd+)" 2>/dev/null); [ -n "$t" ] && printf "%s" "$t" | wl-copy && echo ok']
    stdout: StdioCollector { onStreamFinished: { root.ocrState = text.trim() === "ok" ? "copied" : "empty"; ocrClear.restart() } }
  }
  Timer { id: ocrClear; interval: 8000; onTriggered: root.ocrState = "" }

  // VPN (Proton): its GTK app has no CLI, it brings up a NetworkManager connection named "ProtonVPN ..." while connected.
  // Enter: connected = bring that connection down; not connected = open the Proton app to pick a server.
  property string vpn: ""                 // active Proton connection name, "" = off
  Process {
    id: vpnPoll
    command: ["sh", "-c", "nmcli -t -f NAME con show --active 2>/dev/null | grep -i -m1 proton"]
    stdout: StdioCollector { onStreamFinished: root.vpn = text.trim() }
  }
  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!vpnPoll.running) vpnPoll.running = true }
  function vpnToggle() {
    if (vpn) { Quickshell.execDetached(["nmcli", "con", "down", "id", vpn]); vpn = ""; vpnRecheck.restart() }
    else { closeLauncher(); Quickshell.execDetached(["protonvpn-app"]) }
  }
  Timer { id: vpnRecheck; interval: 3000; onTriggered: vpnPoll.running = true }
  // one Timer item (stopwatch + countdown): length 0 = stopwatch (counts up). Enter = start / pause / go on;
  // Shift+Enter or right click = reset while it runs or is paused, or the next length while idle (Settings -> Tools too).
  readonly property var lengths: [0, 5, 10, 15, 25, 30, 60]
  readonly property int timerMin: Number(Prefs.get("tools_timer_min", 10))
  property real now: Date.now()
  property bool tRun: false
  property real tStart: 0
  property real tAcc: 0                   // ms already counted before the current run
  readonly property bool tIdle: !tRun && tAcc === 0
  readonly property real tTotal: timerMin * 60000
  readonly property real tElapsed: tAcc + (tRun ? now - tStart : 0)
  readonly property real tShown: timerMin > 0 ? Math.max(0, tTotal - tElapsed) : tElapsed
  function tToggle() { if (tRun) { tAcc += Date.now() - tStart; tRun = false } else { tStart = Date.now(); now = tStart; tRun = true } }
  function tReset() { if (tIdle) { const i = lengths.indexOf(timerMin); Prefs.set("tools_timer_min", lengths[(i + 1) % lengths.length]) } else { tRun = false; tAcc = 0 } }
  function mmss(ms) { const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), p = n => String(n).padStart(2, "0"); return (h ? h + ":" + p(Math.floor(s % 3600 / 60)) : Math.floor(s / 60)) + ":" + p(s % 60) }
  Timer {
    interval: 250; repeat: true; running: root.tRun
    onTriggered: { root.now = Date.now(); if (root.timerMin > 0 && root.tElapsed >= root.tTotal) { root.tRun = false; root.tAcc = 0; Sounds.play("dialog-warning", true); Quickshell.execDetached(["notify-send", "-a", "LWTS", "Timer", root.timerMin + " min are up"]) } }
  }
}
