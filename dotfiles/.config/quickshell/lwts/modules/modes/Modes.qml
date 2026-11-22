// Modes (launcher v2 round 8): one press = a set of changes, the next press puts everything back the way it was.
//   focus  - Do not disturb (popups only as the red dot) + pomodoro work / break (modes_focus_work / _break min), a sound at each switch
//   sleep  - Night light on, volume capped (modes_sleep_volume %), the power timer started (its own action / minutes)
//   stream - notifications silenced (nothing pops, no sound) + Caffeine (no sleep, no screen-off)
// Only what a mode itself switched on is switched back off. One mode at a time; other modules are reached through Tiles.all.
pragma Singleton
import QtQuick
import Quickshell
import qs.core
import Quickshell.Io
import qs.services

Singleton {
  id: root
  property string mode: ""
  property var saved: ({})
  readonly property int workMin: Number(Prefs.get("modes_focus_work", 25))
  readonly property int breakMin: Number(Prefs.get("modes_focus_break", 5))
  property string phase: ""        // focus: "work" | "break"
  property real until: 0
  property real total: 1
  property real now: Date.now()
  readonly property int left: mode === "focus" ? Math.max(0, Math.round((until - now) / 1000)) : 0
  readonly property real progress: mode === "focus" ? Math.max(0, Math.min(1, left * 1000 / total)) : -1
  readonly property string leftText: Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0")

  function tile(id) { return Tiles.all[id] || null }
  function turnOn(id) { const t = tile(id); if (t && !t.on()) { t.act(); return true } return false }
  function turnOff(id) { const t = tile(id); if (t && t.on()) t.act() }
  function phaseTo(p) { phase = p; total = (p === "work" ? workMin : breakMin) * 60000; until = Date.now() + total; now = Date.now() }

  function toggle(m) { const was = mode; if (mode) stop(); if (was !== m) start(m) }
  function start(m) {
    const s = { notif: Prefs.get("notif_mode", "both") };
    if (m === "focus") { Prefs.set("notif_mode", "dot"); phaseTo("work") }
    else if (m === "sleep") { s.night = turnOn("night"); s.vol = Audio.volume; Audio.setVolume(Math.min(Audio.volume, Number(Prefs.get("modes_sleep_volume", 30)) / 100)); s.timer = turnOn("powertimer") }
    else if (m === "stream") { Prefs.set("notif_mode", "silence"); s.caf = turnOn("caffeine") }
    saved = s; mode = m;
  }
  function stop() {
    const s = saved;
    if (s.notif !== undefined) Prefs.set("notif_mode", s.notif);
    if (s.night) turnOff("night");
    if (s.vol !== undefined) Audio.setVolume(s.vol);
    if (s.timer) turnOff("powertimer");
    if (s.caf) turnOff("caffeine");
    mode = ""; phase = ""; saved = ({});
  }
  IpcHandler {   // hotkeys / scripts: qs ipc -c lwts call modes toggle focus|sleep|stream
    target: "modes"
    function toggle(m: string): void { root.toggle(m) }
    function status(): string { return root.mode === "focus" ? "focus " + root.phase + " " + root.leftText : root.mode || "off" }
  }
  Timer {
    interval: 1000; repeat: true; running: root.mode === "focus"
    onTriggered: { root.now = Date.now(); if (root.now >= root.until) { root.phaseTo(root.phase === "work" ? "break" : "work"); Sounds.play("dialog-warning", true) } }
  }
}
