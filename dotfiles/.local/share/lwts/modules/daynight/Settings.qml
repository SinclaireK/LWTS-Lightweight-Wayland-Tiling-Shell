// The "Night light" page of Settings -> Features (moved from settings/SettingsNew.qml).
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "features"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function cycle(label, desc, options, get, set) { return { type: "cycle", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  function timeOptions() { const o = []; for (let h = 0; h < 24; h++) for (const m of ["00", "30"]) { const t = String(h).padStart(2, "0") + ":" + m; o.push([t, t]) } return o }
  property var rows: [
      tab("Night light"),
      header("Light"),
      choice("State", "", [["off", "Off"], ["on", "On"]],
             () => Night.on ? "on" : "off", v => { if ((v === "on") !== Night.on) Night.toggle() }),
      { type: "slider", label: "Warmth", desc: "Lower = warmer", steps: [2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500], unit: "K",
        get: () => Number(Prefs.get("nightlight_temp", 4000)), set: v => Look.oldSet("nightlight_temp", v) },
      header("Schedule"),
      choice("Schedule", "", [["manual", "Manual"], ["sun", "Sunset"], ["time", "Own time"]],
             () => Prefs.get("nightlight_mode", "manual"), v => Look.oldSet("nightlight_mode", v)),
      cycle("Starts (night)", "Own time mode", timeOptions(),
            () => Prefs.get("nightlight_night", "21:00"), v => Look.oldSet("nightlight_night", v)),
      cycle("Starts (day)", "Own time mode", timeOptions(),
            () => Prefs.get("nightlight_day", "07:00"), v => Look.oldSet("nightlight_day", v)),
  ]
}
