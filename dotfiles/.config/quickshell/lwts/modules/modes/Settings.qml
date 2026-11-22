// Settings -> Features -> Modes
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "preferences"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property var rows: [
    tab("Modes"),
    header("Focus"),
    choice("Work", "Pomodoro work part", [[15, "15 min"], [25, "25 min"], [45, "45 min"], [50, "50 min"], [90, "90 min"]],
           () => Number(Prefs.get("modes_focus_work", 25)), v => Prefs.set("modes_focus_work", v)),
    choice("Break", "", [[5, "5 min"], [10, "10 min"], [15, "15 min"]], () => Number(Prefs.get("modes_focus_break", 5)), v => Prefs.set("modes_focus_break", v)),
    header("Sleep"),
    choice("Volume cap", "Night light + this volume + the power timer", [[10, "10%"], [20, "20%"], [30, "30%"], [50, "50%"]],
           () => Number(Prefs.get("modes_sleep_volume", 30)), v => Prefs.set("modes_sleep_volume", v)),
  ]
}
