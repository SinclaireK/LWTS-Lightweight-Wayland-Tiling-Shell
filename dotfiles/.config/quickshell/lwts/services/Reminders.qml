// Reminders: items of the note "Plans" (see plans.js) with a date fire a notification when their time comes (no time = 09:00).
// Checked every 20 s; only items that came due in the last 10 minutes fire (a shell restart does not replay old ones); each fires once per session.
// Started from shell.qml (Reminders.start()). The toast is a plain `notify-send` (app "Reminder"), so it goes through the normal notification centre.
pragma Singleton
import QtQuick
import Quickshell
import "../modules/notes"
import "plans.js" as Plans
import qs.core
import qs.services

Singleton {
  id: root
  property var fired: ({})
  function start() {}
  readonly property bool on: Modules.enabled("notes")
  function check() {
    if (!on) return
    const note = Notes.items.find(n => Plans.isPlans(n)); if (!note) return
    const now = Date.now()
    for (const t of Plans.parse(note.text)) {
      if (t.done || t.date === "") continue
      const at = new Date(t.date + "T" + (t.time || "09:00") + ":00").getTime()
      const key = t.date + " " + (t.time || "09:00") + " " + t.text
      if (isNaN(at) || at > now || now - at > 10 * 60000 || fired[key]) continue
      fired[key] = true
      Quickshell.execDetached(["notify-send", "-a", "Reminder", "-i", "alarm-clock", (t.time || "Today") + " · Reminder", t.text])
    }
  }
  Timer { interval: 20000; running: root.on; repeat: true; triggeredOnStart: true; onTriggered: { if (!Notes.ready) Notes.reload(); root.check() } }
}
