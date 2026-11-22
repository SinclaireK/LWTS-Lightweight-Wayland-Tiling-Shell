// Session toggles: caffeine (IdleInhibitor in the bar window), night light, dark mode, game mode, power profile,
// AI panel mode, power actions. Dark mode, profile and night light are native (Look.engine, Session.setProfile, themes/daynight.lua for schedules).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core

Singleton {
  id: root
  readonly property string home: Quickshell.env("HOME")
  readonly property string scripts: Quickshell.shellDir + "/scripts"
  property bool game: false
  readonly property bool dark: Theme.data.mode !== "light"
  readonly property string profile: Prefs.get("power_profile", "auto")   // auto | balanced | performance | power saver

  readonly property var profiles: ["auto", "balanced", "performance", "power saver"]
  // Laptop on mains: "auto" picks Performance there (TLP's balanced profile uses the battery settings even on AC), Balanced otherwise
  readonly property bool acLaptop: !!UPower.displayDevice && UPower.displayDevice.isLaptopBattery && !UPower.onBattery
  onAcLaptopChanged: if (profile === "auto" && !(game && gameOn("game_power"))) { profileSync.pending = "auto"; profileSync.restart() }
  function setProfile(name) {
    if (!profiles.includes(name)) return;
    Prefs.set("power_profile", name);
    profileSync.pending = name; profileSync.restart();
  }
  // One write per burst of clicks (each applyProfile starts a detached tlp run, they raced and left power-saver), and once at start so the
  // daemon follows the saved pref again after a restart
  Timer {
    id: profileSync
    property string pending: ""
    interval: 300; running: true
    onTriggered: root.applyProfile(pending !== "" ? pending : (root.game && root.gameOn("game_power") ? "performance" : root.profile))
  }
  // Over D-Bus (UPower.PowerProfiles): power-profiles-daemon on the desktop, tlp-pd on TLP laptops
  function applyProfile(name) {
    if (name === "auto") name = acLaptop ? "performance" : "balanced";
    if (name === "power saver") PowerProfiles.profile = PowerProfile.PowerSaver;
    else if (name === "performance") PowerProfiles.profile = PowerProfile.Performance;   // not hasPerformanceProfile: false under tlp-pd (no "Driver" key)
    else PowerProfiles.profile = PowerProfile.Balanced;
  }
  function cycleProfile() { setProfile(profiles[(profiles.indexOf(profile) + 1) % profiles.length]) }
  function toggleDark() { Look.toggleDark() }
  readonly property bool stacking: false   // Hyprland-only mode (every window floating); niri has no such mode
  // Lite (game mode), native: what it switches off is up to the game_* options (default on). Compositor-side effects
  // (animations, blur, rounding) are applied by NiriConf, which reads `game`; the shell's own look through Theme.
  function gameOn(id) { return Prefs.get(id, true) !== false }
  function toggleGame() { game = !game }
  onGameChanged: {
    Theme.playing = game; Theme.game = game && gameOn("game_transparency"); Theme.lite = game && gameOn("game_bar_margins");
    if (gameOn("game_power")) applyProfile(game ? "performance" : profile);
  }
  // "Start with a Steam game": Lite while a Steam game window exists, back when the last closes; a Lite started by hand is left alone
  readonly property int steamGames: Compositor.windowList.filter(w => /^steam_app_\d+$/.test(w.app_id || "")).length
  property bool autoGame: false
  onSteamGamesChanged: {
    if (Prefs.get("game_auto", false) !== true && !autoGame) return;
    if (steamGames > 0 && !game) { autoGame = true; game = true }
    else if (steamGames === 0 && wrapped === 0 && autoGame) { autoGame = false; if (game) game = false }
  }
  // `lwts-game %command%` (Steam launch option) reports the game's pid by ipc: Lite for any game, native ones too (their window is not steam_app_N).
  // The shell polls /proc itself (no counter that a lost "stop" call could leave stuck): a dead or zombie pid ends the game.
  property var wrapPids: []
  readonly property int wrapped: wrapPids.length
  function wrapPid(pid) {
    if (!(pid > 1) || wrapPids.includes(pid)) return;
    wrapPids = wrapPids.concat([pid]);
    if (!game) { autoGame = true; game = true }
  }
  function wrapStart() {}   // old wrapper (games started before the update): ignored, the new one sends wrapPid
  function wrapStop() {}
  function wrapEnded(alive) {
    wrapPids = wrapPids.filter(p => alive.includes(p));
    if (wrapped === 0 && steamGames === 0 && autoGame) { autoGame = false; if (game) game = false }
  }
  Timer {
    interval: 2000; repeat: true; running: root.wrapped > 0
    onTriggered: if (!wrapCheck.running) { wrapCheck.command = ["sh", "-c",
      "for p; do grep -qE '^State:[[:space:]]+[^Z[:space:]]' /proc/$p/status 2>/dev/null && echo $p; done", "sh"].concat(root.wrapPids.map(String)); wrapCheck.running = true }
  }
  Process {
    id: wrapCheck
    stdout: StdioCollector { onStreamFinished: root.wrapEnded(text.split("\n").filter(x => x).map(Number)) }
  }
  function refresh() {}   // kept for callers; every state here is event-driven

  // Lite on low battery (laptop; Settings -> Other -> Lite at): on below the threshold, off again when charging
  readonly property int liteAt: Number(Prefs.get("lite_battery", 0))   // %, 0 = never
  readonly property var bat: UPower.displayDevice
  readonly property bool low: liteAt > 0 && !!bat && bat.isLaptopBattery && bat.state === UPowerDeviceState.Discharging
                              && bat.percentage * 100 <= liteAt
  readonly property bool saver: Prefs.get("lite_saver", false) === true && profile === "power saver"   // Settings -> Power -> Lite: the Saver profile turns Lite on
  readonly property bool wantLite: low || saver
  property bool autoLite: false
  onWantLiteChanged: {
    if (wantLite && !game) { autoLite = true; toggleGame() }
    else if (!wantLite && autoLite) { autoLite = false; if (game) toggleGame() }
  }   // states that have no event (on launcher open)

  // power: lock is instant, the rest are confirmed by the UI (hold)
  function power(what) {
    if (what === "lock") { Lock.lock(); return }
    if (what === "logout") { Compositor.logout(); return }
    const cmd = ({ sleep: ["bash", scripts + "/sleep-now.sh"],
                   reboot: ["systemctl", "reboot"],
                   poweroff: ["systemctl", "poweroff"] })[what];
    if (cmd) Quickshell.execDetached(cmd);
  }

  readonly property bool barHidden: false   // Smart Hide needs the compositor's fullscreen state; not ported yet
}
