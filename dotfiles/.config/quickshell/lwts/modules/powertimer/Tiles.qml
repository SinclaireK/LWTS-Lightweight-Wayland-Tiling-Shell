import QtQuick
import qs.services
QtObject {
  property var defs: ({
    // Enter = start the last used timer / cancel; Shift+Enter or right click = the panel. Running: a draining ring + big countdown
    powertimer: { api: PowerTimer, icon: "timer", label: () => PowerTimer.on ? PowerTimer.label(PowerTimer.action) : "Power timer",
                  status: () => PowerTimer.on ? PowerTimer.leftText : PowerTimer.label(PowerTimer.nextAction) + " · " + PowerTimer.nextMinutes + " min",
                  progress: () => PowerTimer.on ? PowerTimer.progress : -1,
                  face: () => PowerTimer.on ? { status: PowerTimer.label(PowerTimer.action), hero: PowerTimer.leftText }
                                            : { status: PowerTimer.label(PowerTimer.nextAction) + " · " + PowerTimer.nextMinutes + " min" },
                  on: () => PowerTimer.on, act: () => PowerTimer.toggle(), panel: "powertimer" }
  })
}
