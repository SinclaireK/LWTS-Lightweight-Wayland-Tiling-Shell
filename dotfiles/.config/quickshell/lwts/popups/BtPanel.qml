// Bluetooth (Super+Alt+B; Quick settings tile): panel-style - hero = connected count + switch, devices (LED = connected, battery dots),
// Scan / settings in one line. Click or Enter = connect / disconnect. Up to 6 rows, the rest is a count (no scrolling).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.core
import qs.widgets
import "panelkeys.js" as PK

ColumnLayout {
  id: p
  spacing: 6
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  Keys.onPressed: e => { if (e.key === Qt.Key_Escape) closeMe(); else if (!PK.handle(p, e)) return; e.accepted = true }
  readonly property var ad: Bluetooth.defaultAdapter
  readonly property var devs: Bluetooth.devices.values.filter(d => d.paired || d.connected || (p.ad && p.ad.discovering))
                                .sort((a, b) => b.connected - a.connected || b.paired - a.paired)
  readonly property bool on: !!ad && ad.enabled
  readonly property int nConn: devs.filter(d => d.connected).length
  readonly property int shown: 6
  component Cap: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }

  // ---- hero: how many devices are connected; the adapter switch on the right (click or Enter)
  MouseArea {
    id: hero
    Layout.fillWidth: true; implicitHeight: 44
    property bool focused: false
    signal act()
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: act()
    onAct: if (p.ad) p.ad.enabled = !p.ad.enabled
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: hero.focused ? Theme.fillHover : hero.containsMouse ? Theme.fill : "transparent" }
    RowLayout {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 } spacing: 6
      UiNum { size: Math.round(32 * Theme.scale); text: p.on ? p.nConn : "OFF"; opacity: p.on ? 1 : 0.35 }
      Cap { text: p.on ? (p.nConn === 1 ? "device connected" : "devices connected") : "Bluetooth"; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
      Item { Layout.fillWidth: true }
      UiToggle { on: p.on; enabled: false; focusedChip: hero.focused }
    }
  }
  UiDotLine { Layout.fillWidth: true; visible: p.on }
  Repeater {
    model: p.on ? p.devs.slice(0, p.shown) : []
    ListRow {
      required property var modelData
      Layout.fillWidth: true; led: true
      meter: modelData.batteryAvailable ? modelData.battery : -1
      title: modelData.name || modelData.address; on: modelData.connected
      trail: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : modelData.connected ? "On" : ""
      onAct: modelData.connected ? modelData.disconnect() : modelData.connect()
    }
  }
  Cap { visible: p.on && p.devs.length > p.shown; text: "+" + (p.devs.length - p.shown) + " more"; Layout.leftMargin: 4 }
  Cap { visible: p.on && p.devs.length === 0; text: "No devices yet - press Scan"; Layout.leftMargin: 4 }
  RowLayout {
    visible: p.on; Layout.fillWidth: true; Layout.rightMargin: 4; spacing: 8
    Item { Layout.fillWidth: true }
    UiButton { text: p.ad && p.ad.discovering ? "Scanning…" : "Scan"; on: !!p.ad && p.ad.discovering; onClicked: p.ad.discovering = !p.ad.discovering }
    UiButton { text: "All settings"; onClicked: { p.closeMe(); Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "settingsId", "bluetooth"]) } }
  }
}
