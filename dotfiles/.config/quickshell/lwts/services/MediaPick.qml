// The one answer to "which media player does the shell show": the preferred music app first (settings.toml media_prefer, default
// "spotify"), so pausing the music does not hand the bar over to a browser tab (YouTube, Helium); then a playing player; then the first.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.core

Singleton {
  id: root
  readonly property var players: Mpris.players.values.filter(p => !(p.dbusName || "").includes("playerctld"))
  readonly property string prefer: String(Prefs.get("media_prefer", "spotify")).toLowerCase()
  readonly property var preferred: prefer === "" ? null : (players.find(p => ((p.dbusName || "") + " " + (p.identity || "")).toLowerCase().includes(prefer)) || null)
  readonly property var player: preferred || players.find(p => p.isPlaying) || players[0] || null
}
