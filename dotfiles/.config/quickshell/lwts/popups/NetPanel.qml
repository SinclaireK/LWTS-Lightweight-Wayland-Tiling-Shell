// Network (bar: network icon, Super+Alt+W): interfaces with live load and rates (disk style), local / public IP (blurred until hover or key) and DNS
// with presets, Wi-Fi networks, and a speed test with latency under load. Rows with `focused` + `act` are reached with the arrow keys (panelkeys).
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.core
import qs.services
import qs.widgets
import "panelkeys.js" as PK

ColumnLayout {
  id: p
  spacing: 6
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  Keys.onPressed: e => { if (e.key === Qt.Key_Escape) closeMe(); else if (!PK.handle(p, e)) return; e.accepted = true }
  readonly property var devs: Networking.devices.values.slice().sort((a, b) => (a.type === DeviceType.Wifi) - (b.type === DeviceType.Wifi))
  readonly property var wired: devs.find(d => d.type !== DeviceType.Wifi && d.connected)
  readonly property var wifi: devs.find(d => d.type === DeviceType.Wifi)
  readonly property var online: wired || (wifi && wifi.connected ? wifi : null)
  Component.onCompleted: { if (wired) NetInfo.load(wired.name); if (online) NetInfo.loadDns(online.name); NetInfo.loadPublic() }
  onWiredChanged: if (wired) NetInfo.load(wired.name)
  onOnlineChanged: if (online) NetInfo.loadDns(online.name)

  component Cap: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  component Val: Text { color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
  component Head: UiCaption { Layout.topMargin: 4 }

  // ---- interfaces: every real one (no lo / docker / bridges / veth); rate from /proc/net/dev every second, totals since boot, link speed from sysfs
  property var nics: []
  property var nicRates: ({})
  property var lastNic: ({})
  property var nicSpeed: ({})   // name -> MB/s of the link
  property var nicUp: ({})      // name -> link is up
  readonly property var nicsUp: nics.filter(x => nicUp[x.n])
  function nicLabel(n) { return /^w/.test(n) ? "WIFI" : /^(en|eth)/.test(n) ? "ETH" : /^(tailscale|wg|tun)/.test(n) ? "VPN" : n.toUpperCase() }
  function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(1) + "T" : b >= 1e9 ? (b / 1e9).toFixed(b >= 1e10 ? 0 : 1) + "G" : Math.round(b / 1e6) + "M" }
  function rate(b) { return b >= 1048576 ? (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) : (b / 1024).toFixed(0) }
  function unit(b) { return b >= 1048576 ? "M" : "K" }
  FileView {
    id: netF; path: "/proc/net/dev"; printErrors: false
    onLoaded: {
      const list = [], rates = {}, last = {};
      for (const l of text().split("\n").slice(2)) {
        const m = l.trim().split(/[:\s]+/);
        if (m.length < 10 || /^(lo|docker|br-|veth|virbr)/.test(m[0])) continue;
        const rx = Number(m[1]), tx = Number(m[9]);
        list.push({ n: m[0], rx: rx, tx: tx }); last[m[0]] = [rx, tx];
        if (p.lastNic[m[0]]) rates[m[0]] = { r: Math.max(0, rx - p.lastNic[m[0]][0]), w: Math.max(0, tx - p.lastNic[m[0]][1]) };
      }
      p.lastNic = last; p.nicRates = rates; p.nics = list;
    }
  }
  Process {
    id: spdP; command: ["sh", "-c", "for i in /sys/class/net/*; do echo $(basename $i) $(cat $i/operstate) $(cat $i/speed 2>/dev/null); done"]
    stdout: StdioCollector { onStreamFinished: { const o = {}, u = {}; for (const l of text.split("\n")) { const a = l.trim().split(" "); if (a.length >= 2) { u[a[0]] = a[1] === "up" || a[1] === "unknown"; o[a[0]] = Number(a[2]) > 0 ? Number(a[2]) / 8 : 12.5 } } p.nicSpeed = o; p.nicUp = u } }
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: netF.reload() }
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: spdP.running = true }
  Repeater {
    model: p.nicsUp.length
    RowLayout {
      required property int index
      readonly property var d: p.nicsUp[index] || ({ n: "", rx: 0, tx: 0 })
      readonly property var io: p.nicRates[d.n] || ({ r: 0, w: 0 })
      readonly property real load: Math.sqrt(Math.min(1, Math.max(io.r, io.w) / ((p.nicSpeed[d.n] || 12.5) * 1048576)))   // sqrt: a few MB/s still shows on a gigabit link
      Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 8
      Cap { text: p.nicLabel(d.n); color: Theme.text; Layout.preferredWidth: Math.round(44 * Theme.scale) }
      Item {
        Layout.fillWidth: true; implicitHeight: 5
        DotMeter { anchors.verticalCenter: parent.verticalCenter; fit: parent.width; dotSize: 3; gap: 2; value: load; hot: 0.9; hotColor: Theme.red }
      }
      Row {
        spacing: 6
        Repeater {
          model: [{ k: "↓", b: io.r }, { k: "↑", b: io.w }]
          Row {
            required property var modelData
            spacing: 3; width: Math.round(46 * Theme.scale)
            Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.text; opacity: modelData.b > 0 ? 1 : 0.16 }
            Cap { text: modelData.k; width: Math.round(8 * Theme.scale) }
            Val { text: p.rate(modelData.b) + p.unit(modelData.b); color: modelData.b > 0 ? Theme.text : Theme.dim }
          }
        }
      }
    }
  }

  // ---- Wi-Fi
  Head { visible: !!p.wifi; text: "Wi-Fi" }
  Repeater {
    model: p.wifi && p.wifi.networks ? p.wifi.networks.values.slice().sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength).slice(0, 8) : []
    ListRow {
      required property var modelData
      Layout.fillWidth: true
      led: true; meter: modelData.signalStrength
      title: modelData.name; on: modelData.connected
      trail: modelData.connected ? "Connected" : ""
      onAct: modelData.connected ? modelData.disconnect() : modelData.connect()
    }
  }

  // ---- speed test (NetInfo.speedTest: Cloudflare over curl, the load shows on the interface meter above)
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 4 }
  MouseArea {
    id: sp
    Layout.fillWidth: true; implicitHeight: 52
    property bool focused: false
    signal act()
    readonly property var r: NetInfo.speed
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: act()
    onAct: NetInfo.speedTest()
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: sp.focused ? Theme.fillHover : sp.containsMouse ? Theme.fill : "transparent" }
    RowLayout {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 } spacing: 14
      Repeater {
        model: [{ k: "↓", v: sp.r.down }, { k: "↑", v: sp.r.up }]
        Row {
          required property var modelData
          spacing: 4; Layout.alignment: Qt.AlignVCenter
          Cap { text: modelData.k; anchors.baseline: num.baseline; color: Theme.text }
          UiNum { id: num; size: Math.round(24 * Theme.scale); text: modelData.v !== undefined ? Math.round(modelData.v) : "–"; opacity: NetInfo.testing ? 0.5 : 1 }
        }
      }
      Cap { text: "Mbit/s"; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 12 }
      Item { Layout.fillWidth: true }
      UiButton { text: NetInfo.testing ? ({ ping: "Latency…", down: "Download…", up: "Upload…" })[NetInfo.phase] || "Testing…" : sp.r.failed ? "Retry" : "Test"; on: NetInfo.testing; enabled: !NetInfo.testing; onClicked: NetInfo.speedTest() }
    }
    }
  RowLayout {   // latency block: idle ping, jitter, loss, and the same ping while the line is full (the bufferbloat)
    visible: sp.r.ping !== undefined
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 12
    Repeater {
      model: [{ k: "Ping", v: sp.r.ping !== undefined ? sp.r.ping.toFixed(0) + " ms" : "" }, { k: "Load ↓↑", v: sp.r.ldown !== undefined ? sp.r.ldown.toFixed(0) + " / " + (sp.r.lup !== undefined ? sp.r.lup.toFixed(0) : "–") : "" },
              { k: "Jitter", v: sp.r.jitter !== undefined ? sp.r.jitter.toFixed(1) : "" },
              { k: "Loss", v: sp.r.loss !== undefined ? sp.r.loss + "%" : "" }]
      Row {
        required property var modelData
        spacing: 4
        Cap { text: modelData.k }
        Val { text: modelData.v; color: modelData.k === "Loss" && sp.r.loss > 0 ? Theme.red : Theme.text }
      }
    }
    Item { Layout.fillWidth: true }
    Cap { text: sp.r.at ? Qt.formatTime(new Date(sp.r.at), "hh:mm") : "" }
  }
  property string sect: ""   // "" | "details" | "settings": one block open at a time, so the tab never scrolls
  Connections { target: NetInfo; function onDnsChanged() { NetInfo.loadSet() } }
  component Tog: MouseArea {   // section toggle: Details / Settings
    id: tg
    property string name
    property string key
    property bool focused: false
    signal act()
    Layout.fillWidth: true; implicitHeight: 28
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: act()
    onAct: p.sect = p.sect === key ? "" : key
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: tg.focused ? Theme.fillHover : tg.containsMouse ? Theme.fill : "transparent" }
    RowLayout {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
      Cap { text: tg.name; color: p.sect === tg.key ? Theme.text : Theme.dim }
      Item { Layout.fillWidth: true }
      Icon { name: p.sect === tg.key ? "caret-up" : "caret-down"; color: Theme.dim }
    }
  }
  RowLayout {
    Layout.fillWidth: true; spacing: 8
    Tog { name: "Details"; key: "details" }
    Tog { name: "Settings"; key: "settings" }
  }

  // ---- a row is a key / value; click or Enter copies; `secret` values are blurred until hover or keyboard focus
  component InfoRow: MouseArea {
    id: ir
    property string k
    property string v
    property string extra: ""
    property bool secret: false
    property bool focused: false
    signal act()
    property bool revealed: false
    readonly property bool shown: !secret || revealed
    Layout.fillWidth: true; implicitHeight: 24
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: act()
    onVisibleChanged: if (!visible) revealed = false
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: ir.focused ? Theme.fillHover : ir.containsMouse ? Theme.fill : "transparent" }
    RowLayout {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
      Cap { text: ir.k; Layout.preferredWidth: Math.round(54 * Theme.scale) }
      Val {
        id: vt; text: ir.v || "…"; Layout.fillWidth: true; elide: Text.ElideRight
        layer.enabled: !ir.shown
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 2.0; autoPaddingEnabled: false }
      }
      Cap { text: ir.extra; visible: ir.extra !== ""; elide: Text.ElideRight; Layout.maximumWidth: Math.round(150 * Theme.scale) }
    }
  }
  component SwRow: MouseArea {   // a switch row (Settings)
    id: sr
    property string k
    property bool on
    property bool focused: false
    signal act()
    Layout.fillWidth: true; implicitHeight: 28
    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: act()
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: sr.focused ? Theme.fillHover : sr.containsMouse ? Theme.fill : "transparent" }
    RowLayout {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
      Cap { text: sr.k; color: Theme.text }
      Item { Layout.fillWidth: true }
      UiToggle { on: sr.on; focusedChip: sr.focused; enabled: false }
    }
  }

  ColumnLayout {
    id: det
    visible: p.sect === "details" || Layout.preferredHeight > 0.5; clip: true; Layout.fillWidth: true; spacing: 6
    Layout.preferredHeight: p.sect === "details" ? implicitHeight : 0
    Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.off ? 0 : Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
    InfoRow {
      k: "Local"; v: p.online ? (NetInfo.info.ip || "…") : "Not connected"
      extra: p.wired ? "GW " + (NetInfo.info.gw || "—") : ""
      onAct: if (NetInfo.info.ip) NetInfo.copy(NetInfo.info.ip)
    }
    InfoRow {
      k: "Public"; secret: true; v: NetInfo.pub.ip || ""; extra: NetInfo.pub.isp || ""
      onAct: revealed = !revealed   // click / Enter shows or hides the address
    }
    readonly property var presets: [["auto", "Auto", ""], ["cf", "Cloudflare", "1.1.1.1 1.0.0.1"], ["g", "Google", "8.8.8.8 8.8.4.4"], ["q9", "Quad9", "9.9.9.9 149.112.112.112"]]
    readonly property string dnsId: {   // which preset the connection uses now
      if (NetInfo.dns.auto) return "auto";
      const first = NetInfo.dns.servers[0] || "";
      const m = presets.find(x => x[2] !== "" && x[2].split(" ")[0] === first);
      return m ? m[0] : "custom";
    }
    InfoRow {   // what is in use now; changing it lives in Settings
      k: "DNS"; v: NetInfo.dnsBusy ? "Applying…" : NetInfo.dns.servers.join("  ·  ") || "—"; extra: det.dnsId === "custom" ? "Custom" : ""
      onAct: if (NetInfo.dns.servers.length) NetInfo.copy(NetInfo.dns.servers[0])
    }
  }

  ColumnLayout {
    id: set
    visible: p.sect === "settings" || Layout.preferredHeight > 0.5; clip: true; Layout.fillWidth: true; spacing: 6
    Layout.preferredHeight: p.sect === "settings" ? implicitHeight : 0
    Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.off ? 0 : Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
    Cap { text: NetInfo.dns.conn ? "Profile  ·  " + NetInfo.dns.conn : "No active profile"; Layout.leftMargin: 4; elide: Text.ElideRight; Layout.fillWidth: true }
    SwRow { k: "Auto-connect"; on: NetInfo.cset.auto; visible: !!NetInfo.dns.conn; onAct: NetInfo.setProp("connection.autoconnect", on ? "no" : "yes") }
    SwRow { k: "Metered (limit background traffic)"; on: NetInfo.cset.metered; visible: !!NetInfo.dns.conn; onAct: NetInfo.setProp("connection.metered", on ? "unknown" : "yes") }
    SwRow { k: "IPv6"; on: NetInfo.cset.v6; visible: !!NetInfo.dns.conn; onAct: NetInfo.setProp("ipv6.method", on ? "disabled" : "auto") }
    Cap { text: "DNS"; Layout.leftMargin: 4; Layout.topMargin: 2; visible: !!NetInfo.dns.conn }
    UiSegmented {
      Layout.alignment: Qt.AlignRight; Layout.rightMargin: 4
      options: det.presets.map(x => [x[0], x[1]]); current: det.dnsId
      enabled: !NetInfo.dnsBusy && !!NetInfo.dns.conn
      onPicked: id => NetInfo.setDns(det.presets.find(x => x[0] === id)[2])
    }
    MouseArea {   // your own servers: up to three IPv4 addresses, space or comma separated; Enter applies, Esc leaves the field
      id: cu
      Layout.fillWidth: true; implicitHeight: 32
      property bool focused: false
      signal act()
      readonly property var list: fld.text.split(/[\s,]+/).filter(x => x)
      readonly property bool valid: list.length >= 1 && list.length <= 3 && list.every(x => /^(\d{1,3})(\.\d{1,3}){3}$/.test(x) && x.split(".").every(n => Number(n) <= 255))
      function apply() { if (valid && !NetInfo.dnsBusy) { NetInfo.setDns(list.join(" ")); p.forceActiveFocus() } }
      hoverEnabled: true; cursorShape: Qt.IBeamCursor
      onClicked: fld.forceActiveFocus()
      onAct: fld.forceActiveFocus()
      Rectangle {
        anchors { fill: parent; leftMargin: 4; rightMargin: 4 } radius: Theme.radiusInner; color: "transparent"
        border.width: fld.activeFocus || cu.focused ? 2 : 1
        border.color: fld.activeFocus || cu.focused ? Theme.ring : Theme.edge
        RowLayout {
          anchors { fill: parent; leftMargin: 10; rightMargin: 6 } spacing: 8
          TextInput {
            id: fld
            Layout.fillWidth: true; verticalAlignment: TextInput.AlignVCenter; clip: true
            color: cu.valid || text === "" ? Theme.text : Theme.red; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale)
            onActiveFocusChanged: if (activeFocus) cu.focused = false
            Keys.onReturnPressed: cu.apply()
            Keys.onEnterPressed: cu.apply()
            Keys.onEscapePressed: { text = ""; p.forceActiveFocus() }
            Text { visible: fld.text === "" && !fld.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: "Custom DNS  8.8.8.8 1.1.1.1"; color: Theme.dim; font: fld.font }
          }
          UiButton { text: "Set"; padX: 10; enabled: cu.valid && !NetInfo.dnsBusy; onClicked: cu.apply() }
        }
      }
    }
    SwRow { k: "Wi-Fi radio"; on: Networking.wifiEnabled; visible: !!p.wifi; onAct: Networking.wifiEnabled = !Networking.wifiEnabled }
    RowLayout {
      Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 8
      Item { Layout.fillWidth: true }
      UiButton { text: "Reconnect"; enabled: !!NetInfo.dns.conn && !NetInfo.dnsBusy; onClicked: NetInfo.reconnect() }
      UiButton { text: "All settings"; onClicked: { p.closeMe(); Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "settingsId", p.wifi ? "wifi" : "network"]) } }
    }
  }
}
