// "Power timer" page of Settings -> Features. Same state as the Quick settings tile and its panel.
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "power"
  function choice(label, desc, options, get, set) { return { type: "choice", label, desc, options, get, set } }
  function cycle(label, desc, options, get, set) { return { type: "cycle", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property var rows: [
      tab("Power timer"),
      header("Do it later"),
      cycle("Minutes", "", [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240].map(m => [m, m < 60 ? m + " min" : (m / 60) + " h"]),
            () => PowerTimer.nextMinutes, v => { PowerTimer.remember("", v); if (PowerTimer.on) PowerTimer.set(PowerTimer.action, v) }),
      choice("Action", "", [["sleep", "Sleep"], ["poweroff", "Power off"]],
             () => PowerTimer.on ? PowerTimer.action : PowerTimer.nextAction, v => PowerTimer.setAction(v)),
      choice("Timer", "", [["off", "Off"], ["on", "On"]],
             () => PowerTimer.on ? "on" : "off", v => { if ((v === "on") !== PowerTimer.on) PowerTimer.toggle() }),
      choice("Show in the bar", "A ring and the countdown next to the clock while it runs", [["off", "Off"], ["on", "On"]],
             () => Prefs.get("powertimer_bar", false) ? "on" : "off", v => Prefs.set("powertimer_bar", v === "on")),
      { type: "info", label: "Fires at", value: PowerTimer.on ? Qt.formatTime(new Date(PowerTimer.until), "HH:mm") : "-" },
  ]
}
