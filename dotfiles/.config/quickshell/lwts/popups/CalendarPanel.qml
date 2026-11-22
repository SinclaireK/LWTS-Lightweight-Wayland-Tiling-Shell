// Clock (bar: clock): Nothing calendar - the day as a dot-matrix hero, month browser (wheel / arrows), outlined today + red dot, mono grid.
// Notes live in the "notes" module (Mod+N). Monday first, 6 weeks.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.widgets

RowLayout {
  id: p
  spacing: 10
  property date shown: new Date()
  property date selected: new Date()   // the day the drop's Today block shows (a click on a day picks it)
  property var marks: ({})             // "YYYY-MM-DD" -> count of own items: a small dot under the day
  signal picked(date d)
  readonly property real dropWidth: implicitWidth + 24   // the drop fits the month grid (Popups: 12 px margin each side)
  readonly property date today: new Date()
  property int cellW: 28   // the time drop sets 34 x 22 (a calendar over the Today block)
  property int cellH: 24
  function shift(d) { shown = new Date(shown.getFullYear(), shown.getMonth() + d, 1) }
  readonly property var cells: {
    const first = new Date(shown.getFullYear(), shown.getMonth(), 1), start = (first.getDay() + 6) % 7, out = [];
    for (let i = 0; i < 42; i++) out.push(new Date(shown.getFullYear(), shown.getMonth(), 1 - start + i));
    return out;
  }

  ColumnLayout {
    spacing: 10
    WheelHandler { onWheel: e => p.shift(e.angleDelta.y > 0 ? -1 : 1) }
    ColumnLayout {   // the date: only with a bottom bar (on top the header over the drop carries the date and the time, like the launcher)
      Layout.fillWidth: true
      visible: Prefs.barPosition === "bottom"
      SystemClock { id: nowClock; precision: SystemClock.Minutes }
      UiCaption { text: Qt.formatDate(nowClock.date, "dddd, d MMMM yyyy"); color: Theme.text }
    }
    UiDotLine { Layout.fillWidth: true; visible: Prefs.barPosition === "bottom" }
    RowLayout {   // month browser
      Layout.fillWidth: true
      UiIconButton { icon: "caret-left"; size: 22; onClicked: p.shift(-1) }
      UiCaption { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Qt.formatDate(p.shown, "MMM yyyy"); color: Theme.text }
      UiIconButton { icon: "caret-right"; size: 22; onClicked: p.shift(1) }
    }
    Grid {
      columns: 7; spacing: 2
      Repeater {
        model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
        UiCaption { required property string modelData; required property int index; width: p.cellW; horizontalAlignment: Text.AlignHCenter; text: modelData
                    opacity: index > 4 ? 0.55 : 1 }   // the weekend recedes
      }
      Repeater {
        model: p.cells
        Rectangle {
          id: cell
          required property var modelData
          required property int index
          readonly property bool isToday: modelData.toDateString() === p.today.toDateString()
          readonly property bool inMonth: modelData.getMonth() === p.shown.getMonth()
          width: p.cellW; height: p.cellH; radius: Theme.radiusCtl
          readonly property bool isSel: modelData.toDateString() === p.selected.toDateString()
          readonly property int marked: p.marks[Qt.formatDate(modelData, "yyyy-MM-dd")] || 0
          color: isSel ? Theme.tint : ma.containsMouse && inMonth ? Theme.fillHover : "transparent"
          border.width: isToday ? 1 : 0; border.color: Theme.text   // Nothing: today = an outline + the red dot, never a filled plate
          Text { anchors.centerIn: parent; text: cell.modelData.getDate()
                 color: cell.isSel ? Theme.accent : cell.inMonth ? (cell.index % 7 > 4 ? Theme.dim : Theme.text) : Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.35)
                 font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
          Rectangle { visible: cell.isToday; width: 4; height: 4; radius: 2; color: Theme.red; anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 2 }
          Rectangle { visible: cell.marked > 0; width: 4; height: 2; radius: 1; color: Theme.accent; anchors { bottom: parent.bottom; bottomMargin: 1; horizontalCenter: parent.horizontalCenter } }   // own items on that day
          MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: { p.shown = new Date(cell.modelData.getFullYear(), cell.modelData.getMonth(), 1); p.picked(cell.modelData) } }
        }
      }
    }
  }
}
