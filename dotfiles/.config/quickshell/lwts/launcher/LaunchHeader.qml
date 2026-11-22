// Launcher header (v2): the concept's header on the bar strip. Big dot-matrix time + red dot on the left, the date on the right
// (weekday bright, "12 NOVEMBER 2026" dim). It straddles the bar's strip above the drop and the first rows of the drop (one surface,
// no seam). The time flies in from the bar's own clock and grows (fly 0 -> 1, driven by Launcher.qml).
import QtQuick
import Quickshell
import qs.core
import qs.services
import qs.widgets

Item {
  id: h
  required property var launcher
  readonly property real fly: launcher.fly
  readonly property var bar: launcher.bar
  readonly property int bigSize: Math.round(34 * Theme.scale)
  implicitHeight: bigSize + 6
  opacity: launcher.typing ? 0 : 1   // typing: the date and time fade out, the search takes the whole width
  Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
  readonly property real dateW: dateCol.implicitWidth
  readonly property real clockW: clk.implicitWidth

  SystemClock { id: hc; precision: SystemClock.Minutes }

  Row {
    id: clk
    spacing: 6
    transformOrigin: Item.TopLeft
    readonly property real s0: h.bar.clockItem ? Math.min(1, h.bar.clockItem.font.pixelSize / h.bigSize) : 1
    scale: s0 + (1 - s0) * h.fly
    function fromPt() { return h.bar.clockItem ? h.bar.clockItem.mapToItem(h, 0, 0) : null }
    x: { const p = fromPt(), rest = h.width - clk.implicitWidth; return p ? p.x + (rest - p.x) * h.fly : rest }
    y: { const p = fromPt(), rest = (h.height - clk.height) / 2; return p ? p.y + (rest - p.y) * h.fly - 1 * h.fly : rest - 1 }   // Doto digits sit low in their line box: lift to the optical centre
    opacity: fromPt() ? 1 : h.fly
    UiNum { size: h.bigSize; text: Qt.formatDateTime(hc.date, Prefs.get("clock_24h", true) ? "HH:mm" : "h:mm") }
    Rectangle { y: Math.round(4 * Theme.scale); width: 5; height: 5; radius: 2.5; color: Theme.red; opacity: h.bar.unread > 0 ? 1 : 0 }   // unread dot travels with the time
  }

  Column {   // the date on the left, bottom-aligned with the time
    id: dateCol
    anchors { left: parent.left; verticalCenter: parent.verticalCenter; verticalCenterOffset: 2 }
    spacing: 3
    opacity: h.fly
    UiCaption { color: Theme.text; font.pixelSize: Math.round(12 * Theme.scale); text: Qt.formatDateTime(hc.date, "dddd") }
    UiCaption { text: Qt.formatDateTime(hc.date, "d MMMM yyyy") }
  }
}
