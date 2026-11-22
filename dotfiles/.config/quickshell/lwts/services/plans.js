// Plans = the note "Plans" (Notes module): one line per item, `[ ] 2026-11-25 17:30 text` (date and time optional, a box `[x]` = done).
// Used by the time drop (popups/AgendaPanel.qml) and the reminder timer (services/Reminders.qml).
.pragma library

function parse(text) {   // [{ line, done, date: "YYYY-MM-DD" | "", time: "HH:MM" | "", text }]
  const out = [], ls = String(text).split("\n")
  for (let i = 0; i < ls.length; i++) {
    const m = ls[i].match(/^\s*\[( |x|X)\]\s?(.*)$/); if (!m) continue
    let t = m[2].trim(), date = "", time = ""
    const d = t.match(/^(\d{4}-\d\d-\d\d)\s+(.*)$/); if (d) { date = d[1]; t = d[2] }
    const h = t.match(/^(\d{1,2}):(\d\d)\s+(.*)$/); if (h) { time = (h[1].length < 2 ? "0" : "") + h[1] + ":" + h[2]; t = h[3] }
    if (t.trim() === "") continue
    out.push({ line: i, done: m[1] !== " ", date, time, text: t.trim() })
  }
  return out
}
function isPlans(n) { return String(n.text).split("\n")[0].trim() === "Plans" }
