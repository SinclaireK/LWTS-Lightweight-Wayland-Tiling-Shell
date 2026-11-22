// Settings -> Features -> Tools
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "preferences"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label, page) { return page ? { type: "tab", label, page } : { type: "tab", label } }
  property var rows: [
    tab("Modules", 8),
    header("Timer"),
    choice("Length", "Stopwatch counts up; Enter = start / pause, Shift+Enter = reset (idle: next length)", [[0, "Stopwatch"], [5, "5 min"], [10, "10 min"], [15, "15 min"], [25, "25 min"], [30, "30 min"], [60, "1 h"]],
           () => Number(Prefs.get("tools_timer_min", 10)), v => Prefs.set("tools_timer_min", v)),
    header("Text from screen"),
    { type: "info", label: "OCR engine", value: Tools.hasOcr ? "tesseract" : "not installed (tesseract + tesseract-data-ukr/rus/eng)" },
  ]
}
