// The power list as a floating box under the launcher panel (the panel itself never grows). Rows: Lock; Sleep / Log out / Reboot /
// Power off need a held press; the sleep / power-off timer. State lives in QuickSettings (`qs`): powerOpen, focusId, holding.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.widgets

Item {
  id: pl
  required property var qs
  property bool open: false
  property real k: open ? 1 : 0                 // 0 = folded into the button's row, 1 = fully open
  Behavior on k { NumberAnimation { duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
  visible: k > 0.01
  clip: true
  width: Math.round(128 * Theme.scale)          // place() sets it to the button's width
  readonly property real headH: Math.round(22 * Theme.scale) + 8
  height: headH + (pcol.implicitHeight + 8 - headH) * k
  function place(btn) {   // sit exactly over the POWER button: the same row, the menu grows down from it
    const p = btn.mapToItem(pl.parent, 0, 0);
    width = btn.width + 8; x = p.x - 4; y = p.y - 4
  }
  Rectangle {
    anchors.fill: parent; radius: Theme.radiusCtl
    color: Theme.surface
    border.width: 1; border.color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.35)
  }
  ColumnLayout {
    id: pcol
    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 4 }
    spacing: 0
    MouseArea {   // the head row = the POWER button itself; click / Left / Esc folds
      Layout.fillWidth: true
      implicitHeight: Math.round(22 * Theme.scale)
      cursorShape: Qt.PointingHandCursor
      onClicked: pl.qs.powerOpen = false
      Rectangle {
        anchors.fill: parent; radius: Theme.radiusCtl; color: "transparent"
        border.width: pl.qs.focusId === "p:menu" ? 2 : 0; border.color: Theme.ring
      }
      RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        UiCaption { text: "Power"; color: Theme.text }
        Item { Layout.fillWidth: true }
        UiCaption {
          readonly property var pt: pl.qs.all.powertimer
          visible: !!pt && pt.on()
          text: pt ? pt.status() : ""
          color: Theme.text
        }
        UiCaption { text: "‹" }
      }
    }
    Repeater {   // power list: one quiet row per action (Lock; Sleep / Log out / Reboot / Power off need a held press), then the timer
      model: qs.power
      MouseArea {
        id: pr
        opacity: pl.k
        required property var modelData
        readonly property bool isTimer: modelData.id === "timer"
        visible: qs.powerOpen && (!isTimer || !!qs.all.powertimer)
        readonly property bool focused: qs.focusId === "p:" + modelData.id
        Layout.fillWidth: true
        implicitHeight: Math.round(22 * Theme.scale)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: qs.pressPower(modelData)
        onReleased: qs.releasePower()
        onCanceled: qs.releasePower()
        Rectangle {
          anchors.fill: parent; radius: Theme.radiusCtl; clip: true
          color: pr.containsMouse ? Theme.fillHover : "transparent"
          border.width: pr.focused ? 2 : 0; border.color: Theme.ring
          Rectangle {   // hold fill: sweeps left to right, red
            visible: qs.holding === pr.modelData.id
            width: parent.width * qs.holdP; height: parent.height; radius: parent.radius
            color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.35)
          }
        }
        RowLayout {
          anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
          UiCaption { text: pr.modelData.label; color: qs.holding === pr.modelData.id ? Theme.red : (pr.focused || pr.containsMouse ? Theme.text : Theme.dim) }
          Item { Layout.fillWidth: true }
          UiCaption {
            visible: pr.isTimer && !!qs.all.powertimer && qs.all.powertimer.on()
            text: visible ? qs.all.powertimer.status() : ""
          }
          UiHintBadge { letter: qs.powerHint(pr.modelData.id) }
        }
      }
    }
  }
}
