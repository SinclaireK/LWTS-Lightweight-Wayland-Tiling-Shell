// The "water" tile: a read-only mirror of ~/.local/state/daily-quests.json (daily-quests owns the writes).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
Scope {
  id: root
  property var waterState: ({})
  property var defs: ({
    water: { icon: "drop", label: () => "Water",
             status: () => root.waterState.water_current !== undefined ? root.waterState.water_current + "/" + Prefs.get("quests_water_goal", 8) : "",
             on: () => root.waterState.water_current >= Number(Prefs.get("quests_water_goal", 8)),
             act: () => Quickshell.execDetached(["/usr/bin/luajit", Quickshell.env("HOME") + "/.local/bin/daily-quests", "drink"]) }
  })
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/daily-quests.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.waterState = JSON.parse(text()) } catch (e) { root.waterState = {} } }
  }
}
