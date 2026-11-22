// The "Daily quests" tab of Settings -> Features (moved from settings/SettingsNew.qml). The reminders themselves are run by ~/.local/bin/daily-quests.
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "notifications"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property var rows: [
      tab("Daily quests"),
      header("Hydration"),
      choice("Mode", "Reminder alert mode", [["notify", "Notifications"], ["off", "Off"]],
             () => Prefs.get("quests_water_mode", "notify"), v => Prefs.set("quests_water_mode", v)),
      choice("Interval", "How often to remind", [[45, "45 min"], [60, "1 hour"], [90, "1.5 hours"], [120, "2 hours"]],
             () => Number(Prefs.get("quests_water_interval", 90)), v => Prefs.set("quests_water_interval", v)),
      choice("Goal", "Total glasses per day", [[6, "6 glasses"], [8, "8 glasses (2 L)"], [10, "10 glasses"]],
             () => Number(Prefs.get("quests_water_goal", 8)), v => Prefs.set("quests_water_goal", v)),
      choice("Snooze", "Delay when postponed in alert", [[10, "10 min"], [15, "15 min"], [30, "30 min"]],
             () => Number(Prefs.get("quests_water_snooze", 15)), v => Prefs.set("quests_water_snooze", v)),
      header("Posture & break"),
      choice("Stretch alert", "Stand up and stretch shoulders/back", [["off", "Off"], ["45", "45 min"], ["60", "1 hour"], ["90", "1.5 hours"]],
             () => String(Prefs.get("quests_stretch_interval", "off")), v => Prefs.set("quests_stretch_interval", v)),
      header("Eye rest (20-20-20)"),
      choice("Eye pause", "Short break to look out the window", [["off", "Off"], ["20", "20 min"], ["30", "30 min"], ["45", "45 min"]],
             () => String(Prefs.get("quests_eyes_interval", "off")), v => Prefs.set("quests_eyes_interval", v)),
      header("Digital hygiene"),
      choice("Clean desk", "Evening reminder to clear ~/Downloads & tabs", [["off", "Off"], ["21:00", "21:00"], ["22:00", "22:00"], ["23:00", "23:00"]],
             () => Prefs.get("quests_clean_time", "off"), v => Prefs.set("quests_clean_time", v)),
      header("Sleep schedule"),
      choice("Bedtime alert", "Reminder to wrap up gaming/work", [["off", "Off"], ["23:30", "23:30"], ["00:00", "00:00"], ["00:30", "00:30"], ["01:00", "01:00"]],
             () => Prefs.get("quests_sleep_time", "off"), v => Prefs.set("quests_sleep_time", v)),
  ]
}
