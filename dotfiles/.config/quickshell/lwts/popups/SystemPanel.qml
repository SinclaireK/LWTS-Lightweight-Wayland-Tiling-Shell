// System drop: network and Bluetooth in one drop, one category at a time (bar: the status icons, Super+Alt+W / Super+Alt+B).
// NetPanel and BtPanel stay independent files and are loaded as they are, nothing is copied here. A category without hardware has
// no tab (no Bluetooth adapter = no Bluetooth tab; only one category left = no strip). Popups maps "net" / "bt" / "power" to this drop with that tab chosen.
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.core
import qs.widgets

FocusScope {
  id: p
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  signal pinChanged(bool v)
  property bool pinned: false   // Popups: while pinned the drop ignores click-away and mouse-leave
  readonly property bool keepOpen: pinned
  implicitWidth: 360
  implicitHeight: col.implicitHeight
  readonly property real dropWidth: implicitWidth + 24   // Popups: 12 px margin each side
  property string tab: "net"   // net | bt | power | stats | stats
  readonly property bool btOk: !!Bluetooth.defaultAdapter
  readonly property bool batOk: !!Session.bat && Session.bat.isLaptopBattery
  readonly property bool statsOk: !batOk   // desktop: CPU / GPU / RAM take the place of the laptop's Power category
  readonly property var tabs: [["net", "Network"]].concat(btOk ? [["bt", "Bluetooth"]] : [], batOk ? [["power", "Power"]] : [], statsOk ? [["stats", "Stats"]] : [])
  property real tabK: 1   // the chosen category rises + fades in on every switch
  NumberAnimation { id: tabIn; target: p; property: "tabK"; from: 0; to: 1; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.enterCurve }
  function setTab(t) {
    if (!tabs.some(x => x[0] === t)) t = "net";
    if (t === tab) return;
    tab = t; tabIn.restart();
  }
  onTabsChanged: if (!tabs.some(x => x[0] === tab)) setTab("net")
  Keys.onPressed: e => { if (e.key === Qt.Key_Tab && tabs.length > 1) { setTab(tabs[(tabs.findIndex(x => x[0] === tab) + 1) % tabs.length][0]); e.accepted = true } }   // Tab = next category (rows keep arrows / Enter)

  ColumnLayout {
    id: col
    width: p.width
    spacing: 6
    RowLayout {
      Layout.fillWidth: true; spacing: 8
      UiSegmented { visible: p.tabs.length > 1; options: p.tabs; current: p.tab; onPicked: id => p.setTab(id) }
      UiCaption { visible: p.tabs.length < 2; text: "Network"; color: Theme.text }
      Item { Layout.fillWidth: true }
      UiIconButton { icon: "push-pin"; size: 24; on: p.pinned; onClicked: { p.pinned = !p.pinned; p.pinChanged(p.pinned) } }
    }
    UiDotLine { Layout.fillWidth: true }
    Loader {
      id: body
      Layout.fillWidth: true
      opacity: p.tabK; transform: Translate { y: (1 - p.tabK) * 6 }
      source: p.tab === "bt" ? "BtPanel.qml" : p.tab === "power" ? "PowerPanel.qml" : p.tab === "stats" ? "StatsPanel.qml" : "NetPanel.qml"
      onLoaded: { item.width = Qt.binding(() => body.width); Qt.callLater(() => { if (body.item) body.item.forceActiveFocus() }) }
    }
    Connections { target: body.item; ignoreUnknownSignals: true; function onCloseMe() { p.closeMe() } }
  }
}
