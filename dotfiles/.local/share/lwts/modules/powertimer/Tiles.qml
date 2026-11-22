import QtQuick
import qs.services
QtObject {
  property var defs: ({
    powertimer: { icon: "timer", label: () => "Power timer",
                  status: () => PowerTimer.on ? (PowerTimer.action === "sleep" ? "Sleep" : "Off") + " at " + Qt.formatTime(new Date(PowerTimer.until), "HH:mm") : "",
                  on: () => PowerTimer.on, act: () => PowerTimer.set(PowerTimer.on ? "" : "sleep", 30) }
  })
}
