// Power timer drop (Quick settings tile: Shift+Enter / right click): live countdown, action, time, start / cancel.
// Keys: ↑ ↓ rows, ← → change the row (action / ±5 min), Enter acts, Esc closes. While it runs, a time change moves the end.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets
import "../../popups/panelkeys.js" as PK

ColumnLayout {
  id: p
  spacing: 6
  focus: true
  readonly property bool wantsKeys: true
  readonly property int dropWidth: 320
  signal closeMe()
  Keys.onPressed: e => { if (e.key === Qt.Key_Escape) closeMe(); else if (!PK.handle(p, e)) return; e.accepted = true }

  readonly property string act: PowerTimer.on ? PowerTimer.action : PowerTimer.nextAction

  Column {   // the countdown, big
    Layout.fillWidth: true
    Layout.bottomMargin: 2
    Text { anchors.horizontalCenter: parent.horizontalCenter
           text: PowerTimer.on ? PowerTimer.leftText : PowerTimer.nextMinutes + " min"
           color: PowerTimer.on ? Theme.accent : Theme.dim; font.family: Theme.dot; font.weight: Font.Bold
           font.pixelSize: Math.round(30 * Theme.scale); font.features: { "tnum": 1 } }
    Text { anchors.horizontalCenter: parent.horizontalCenter
           text: PowerTimer.on ? PowerTimer.label(PowerTimer.action) + " at " + Qt.formatTime(new Date(PowerTimer.until), "HH:mm") : "Not running"
           color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
  }

  component Row2: Item {   // a keyboard row (panelkeys.js): focused + act(), nudge(d) for ← →
    id: r
    property bool focused: false
    property string label
    signal act()
    function nudge(d) {}
    default property alias content: slot.data
    Layout.fillWidth: true
    implicitHeight: 30
    Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; color: r.focused ? Theme.fillHover : "transparent"; border.width: 1; border.color: Theme.edge }
    Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
           text: r.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
    Item { id: slot; anchors { right: parent.right; rightMargin: 4; top: parent.top; bottom: parent.bottom } width: childrenRect.width }
  }
  component Seg: UiButton { flat: true; padX: 18 }   // the shared chip, flat inside the joined group

  Row2 {
    label: "Action"
    onAct: PowerTimer.setAction(p.act === "sleep" ? "poweroff" : "sleep")
    function nudge(d) { PowerTimer.setAction(d > 0 ? "poweroff" : "sleep") }
    Row { anchors.verticalCenter: parent.verticalCenter; spacing: 2
      Seg { text: "Sleep"; on: p.act === "sleep"; onClicked: PowerTimer.setAction("sleep") }
      Seg { text: "Power off"; on: p.act === "poweroff"; onClicked: PowerTimer.setAction("poweroff") } }
  }
  Row2 {
    label: PowerTimer.on ? "Add / remove time" : "Time"
    onAct: PowerTimer.toggle()
    function nudge(d) { PowerTimer.add(d > 0 ? 5 : -5) }
    Row { anchors.verticalCenter: parent.verticalCenter; spacing: 2
      Seg { text: "−5"; onClicked: PowerTimer.add(-5) }
      Text { anchors.verticalCenter: parent.verticalCenter; width: 52; horizontalAlignment: Text.AlignHCenter
             text: PowerTimer.on ? PowerTimer.leftText : PowerTimer.nextMinutes + " min"; color: Theme.text
             font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale); font.features: { "tnum": 1 } }
      Seg { text: "+5"; onClicked: PowerTimer.add(5) } }
  }
  Flow {   // presets (mouse): set the time; while running, restart from now with it
    Layout.fillWidth: true
    spacing: 4
    Repeater {
      model: [15, 30, 45, 60, 90, 120]
      Seg { required property int modelData
            text: modelData < 60 ? modelData + " min" : (modelData / 60) + " h"
            on: !PowerTimer.on && PowerTimer.nextMinutes === modelData
            onClicked: { PowerTimer.remember("", modelData); if (PowerTimer.on) PowerTimer.set(PowerTimer.action, modelData) } }
    }
  }
  ListRow {
    Layout.fillWidth: true
    icon: PowerTimer.on ? "stop" : "play"
    title: PowerTimer.on ? "Cancel" : "Start · " + PowerTimer.label(PowerTimer.nextAction).toLowerCase() + " in " + PowerTimer.nextMinutes + " min"
    on: PowerTimer.on
    onAct: PowerTimer.toggle()
  }
}
