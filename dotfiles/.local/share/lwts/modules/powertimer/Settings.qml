// "Power timer" page of Settings -> Features.
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "features"
  function choice(label, desc, options, get, set) { return { type: "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property int minutes: 30
  property var rows: [
      tab("Power timer"),
      header("Do it later"),
      choice("Minutes", "", [[15, "15"], [30, "30"], [45, "45"], [60, "60"]],
             () => PowerTimer.on ? Math.round((PowerTimer.until - Date.now()) / 60000 / 15) * 15 || minutes : minutes,
             v => { minutes = v; if (PowerTimer.on) PowerTimer.set(PowerTimer.action, v) }),
      choice("Action", "Starts the countdown; Off cancels it", [["off", "Off"], ["sleep", "Sleep"], ["poweroff", "Power off"]],
             () => PowerTimer.on ? PowerTimer.action : "off",
             v => PowerTimer.set(v === "off" ? "" : v, minutes)),
      { type: "info", label: "Fires at", value: PowerTimer.on ? Qt.formatTime(new Date(PowerTimer.until), "HH:mm") : "-" },
  ]
}
