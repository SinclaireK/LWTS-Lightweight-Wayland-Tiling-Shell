// The "Caffeine" page of Settings -> Features (moved from settings/SettingsNew.qml).
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "power"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property var rows: [
      tab("Caffeine"),
      header("Keep awake"),
      choice("Mode", "", [["off", "Off"], ["indefinite", "Indefinite"], ["timer", "Timer"]],
             () => !Caffeine.on ? "off" : Caffeine.until > 0 ? "timer" : "indefinite",
             v => v === "off" ? Caffeine.set(-1) : v === "indefinite" ? Caffeine.set(0) : Caffeine.set(30)),
      choice("Timer", "Only while Mode = Timer", [[15, "15 min"], [30, "30 min"], [60, "1 h"], [120, "2 h"], [240, "4 h"]],
             () => Caffeine.until > 0 ? Math.round((Caffeine.until - Date.now()) / 60000) : 30,
             v => Caffeine.set(v)),
      choice("Dark screen only", "Screens still turn off; only system sleep is blocked (downloads / renders)", [["off", "Off"], ["on", "On"]],
             () => Caffeine.darkOnly ? "on" : "off", v => Prefs.set("caffeine_dark_only", v === "on")),
      { type: "info", label: "Resets on reboot", value: "always" },
  ]
}
