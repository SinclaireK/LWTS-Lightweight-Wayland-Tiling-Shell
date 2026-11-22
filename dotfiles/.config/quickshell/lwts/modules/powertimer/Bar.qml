import QtQuick
import qs.core
QtObject {
  // optional live activity in the bar while a timer runs (Settings -> Features -> Power timer -> Show in the bar): ring + countdown; click = the panel, right click = cancel
  property var items: [
    { id: "powertimer", visible: () => PowerTimer.on && Prefs.get("powertimer_bar", false) === true, progress: () => PowerTimer.progress, text: () => PowerTimer.leftText,
      icon: () => PowerTimer.action === "poweroff" ? "power" : "moon", panel: "powertimer", alt: () => PowerTimer.set("", 0) }
  ]
}
