// Desktop widget: dot-matrix clock + date, weather on the right (4x2) or below (2x2). Weather comes from Desk.weather (shared, 30 min).
import QtQuick
import Quickshell
import qs.core
import qs.services
import qs.widgets

UiWidgetCard {
  id: w
  readonly property bool wide: width >= 200
  SystemClock { id: clk; precision: SystemClock.Minutes; enabled: w.awake }

  Column {
    id: left
    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
    spacing: 4
    UiNum { text: Qt.formatDateTime(clk.date, "HH:mm"); size: Math.round(w.height * (w.wide ? 0.38 : 0.28)) }
    UiCaption { text: Qt.formatDate(clk.date, "ddd d MMM") }
  }
  Column {
    visible: Desk.weather.value !== "--" || true
    anchors.right: parent.right
    anchors.verticalCenter: w.wide ? parent.verticalCenter : undefined
    anchors.bottom: w.wide ? undefined : parent.bottom
    spacing: 2
    Icon { anchors.right: parent.right; visible: !!Desk.weather.icon; name: Desk.weather.icon || ""; font.pixelSize: 22 }
    UiNum { anchors.right: parent.right; text: Desk.weather.value; size: 24 }
    UiCaption { anchors.right: parent.right; text: Desk.weather.sub || ""; width: Math.min(implicitWidth, 110); elide: Text.ElideRight; horizontalAlignment: Text.AlignRight; visible: w.wide }
  }
}
