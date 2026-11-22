// Notification pop-ups: a drop out of the bar under the clock (where the notification centre opens) with up to two cards (newest on top).
// Not shown while the notification centre (same spot) is open.
// OPEN / actions = act, × or right click = hide the pop-up (stays in the centre); a click on the text does not close it; they expire by themselves (Notifs).
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

Item {
  id: t
  required property var bar
  property real avoidL: -1   // launcher open on this bar: left edge of its panel; the cards step aside to the left of it, narrower
  readonly property bool aside: avoidL >= 0
  anchors.fill: parent
  readonly property bool atBottom: Prefs.barPosition === "bottom"
  readonly property bool want: Notifs.popups.length > 0 && !(bar.popupDrop && bar.popupDrop.opened && (bar.popupPanel === "notif" || bar.popupPanel === "time"))
  property real clockX: -1   // the clock's x, read each time the pop-up opens (xFor() is a function: a plain binding would keep the value from the shell start, before the bar was laid out = the left corner)
  onWantChanged: { if (want) { clockX = bar.xFor("clock"); drop.open() } else drop.close() }
  Component.onCompleted: bar.toastDrop = drop

  Droplet {
    id: drop
    flip: t.atBottom
    fullWidth: t.aside ? 240 : 300
    fullHeight: col.implicitHeight + 20
    Behavior on fullHeight { enabled: drop.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
    anchorX: t.aside ? t.avoidL - 10 - fullWidth / 2 : t.clockX >= 0 ? t.clockX : t.width   // centred under the clock; no clock in the bar = the right corner (Droplet keeps it inside the screen)
    y: t.atBottom ? t.height - t.bar.barH - height : t.bar.barH
    Column {
      id: col
      x: 10; y: 10; width: drop.fullWidth - 20
      spacing: 2
      Repeater { model: Notifs.popups; NotifCard { required property var modelData; n: modelData; timed: true; width: col.width } }
    }
  }
}
