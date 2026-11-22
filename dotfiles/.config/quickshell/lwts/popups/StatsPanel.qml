// Stats (bar: the CPU / GPU dot columns, System drop category "stats"; desktop, the laptop has Power there). Same layout as PowerPanel:
// hero numeral + caption, a track, a quiet line, a dotted rule, key / value rows. Own panel, independent of SysMonPanel (window title).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
  Component.onCompleted: SysMon.active = true
  Component.onDestruction: SysMon.active = false
  readonly property real ramTotal: SysMon.ram > 0 ? SysMon.ramGb / SysMon.ram : 0

  component Cap: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  component Track: Item {   // the load as a track, like the battery's
    property real value
    Layout.fillWidth: true; implicitHeight: 24
    Rectangle { x: 4; y: 9; width: parent.width - 8; height: 6; radius: 2; color: Theme.line }
    Rectangle {
      x: 4; y: 9; height: 6; radius: 2; color: parent.value > 0.9 ? Theme.red : Theme.text
      width: (parent.width - 8) * Math.max(0, Math.min(1, parent.value))
      Behavior on width { enabled: !Motion.off; NumberAnimation { duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
    }
  }
  component KV: RowLayout {
    property string k
    property string v
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
    Cap { text: parent.k }
    Item { Layout.fillWidth: true }
    Text { text: parent.v; color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
  }

  RowLayout {   // three cells side by side: caption + extra, dot-matrix numeral, dot meter
    Layout.fillWidth: true; spacing: 14
    Repeater {
      model: 3
      ColumnLayout {
        required property int index
        readonly property var it: [{ n: "CPU", v: SysMon.cpu, t: SysMon.cpuTemp, w: p.cpuW, a: SysMon.cpuGhz.toFixed(1) + " GHz" },
                                   { n: "GPU", v: SysMon.gpu, t: SysMon.gpuTemp, w: SysMon.gpuW, a: SysMon.vramUsed.toFixed(1) + " / " + SysMon.vramTotal.toFixed(0) + " G" },
                                   { n: "RAM", v: SysMon.ram, t: 0, w: 0, a: SysMon.ramGb.toFixed(1) + " / " + p.ramTotal.toFixed(0) + " G" }][index]
        readonly property bool alert: it.t >= 80 || it.v >= 0.9   // hot or full: a red dot by the caption (like the clock's unread dot)
        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 3
        RowLayout {
          Layout.fillWidth: true
          Cap { text: it.n; color: Theme.text }
          Rectangle { width: 4; height: 4; radius: 2; color: Theme.red; opacity: alert ? 1 : 0; Layout.alignment: Qt.AlignVCenter; Behavior on opacity { NumberAnimation { duration: Motion.fast } } }
          Cap { visible: it.t > 0; text: it.t + "°" }
          Item { Layout.fillWidth: true }
          Cap { visible: it.w > 0; text: Math.round(it.w) + " W"; color: Theme.text }
          Cap { visible: it.n === "RAM" && SysMon.swapTotal > 0; text: "Swap " + SysMon.swapGb.toFixed(1) + " G"; color: SysMon.swapGb > 0.5 ? Theme.text : Theme.dim }
        }
        RowLayout {
          spacing: 3
          UiNum { text: Math.round(it.v * 100); size: Math.round(26 * Theme.scale); color: it.v > 0.9 ? Theme.red : Theme.text }
          Text { text: "%"; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale); Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 5 }
        }
        Item {
          Layout.fillWidth: true; implicitHeight: 5
          DotMeter {
            anchors.verticalCenter: parent.verticalCenter
            fit: parent.width; dotSize: 3; gap: 2
            value: it.v; hot: 0.9; hotColor: Theme.red
          }
        }
        Cap { text: it.a; Layout.alignment: Qt.AlignLeft }
      }
    }
  }
  Canvas {   // last minute as dot-matrix columns: CPU solid, GPU dimmer where it is above the CPU; a column over 90 % turns red
    id: graph
    Layout.fillWidth: true; Layout.topMargin: 2; implicitHeight: 29
    readonly property var cpuH: SysMon.histCpu
    readonly property var gpuH: SysMon.histGpu
    onCpuHChanged: requestPaint()
    onPaint: {
      const ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
      const rows = 6, pitch = 5, d = 3, cols = Math.floor(width / pitch), n = cpuH.length;
      const txt = Theme.text, red = Theme.red;
      for (let c = 0; c < cols; c++) {
        const k = n - cols + c;   // newest at the right edge
        for (let r = 0; r < rows; r++) {   // r = 0 is the bottom row
          const lc = k >= 0 && k < n && cpuH[k] * rows - r >= 0.5, lg = k >= 0 && k < n && gpuH[k] * rows - r >= 0.5;
          const hot = k >= 0 && k < n && (cpuH[k] > 0.9 || gpuH[k] > 0.9);
          ctx.globalAlpha = lc ? 1 : lg ? 0.45 : 0.14;
          ctx.fillStyle = (lc || lg) && hot ? red : txt;
          ctx.beginPath(); ctx.arc(c * pitch + d / 2 + 1, height - r * pitch - d / 2 - 1, d / 2, 0, Math.PI * 2); ctx.fill();
        }
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 14
    Cap { text: "Last minute" }
    Item { Layout.fillWidth: true }
    Rectangle { width: 6; height: 6; radius: 3; color: Theme.text }
    Cap { text: "CPU" }
    Rectangle { width: 6; height: 6; radius: 3; color: Theme.text; opacity: 0.45 }
    Cap { text: "GPU" }
  }
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
  // CPU package watts: the root sampler lwts-powerd (RAPL is root-only) writes /run/lwts/power while the shell touches WANT; GPU watts: amdgpu hwmon (SysMon)
  property real cpuW: 0
  FileView {
    id: fLive; path: "/run/lwts/power"; printErrors: false
    onLoaded: { const m = text().match(/^pkg=([\d.]+)/m); p.cpuW = m ? Number(m[1]) : 0 }
  }
  FileView { id: fWant; path: Quickshell.env("XDG_RUNTIME_DIR") + "/lwts-power-want"; printErrors: false }
  Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { fLive.reload(); fWant.setText(String(Math.floor(Date.now() / 1000))) } }
  // disks: every physical disk, usage from lsblk (every 30 s), read / write rate from /proc/diskstats (every second)
  property var disks: []   // [{ n, size, used }]
  property var rates: ({})   // name -> { r, w } bytes/s
  property var lastIo: ({})
  function rate(b) { return b >= 1048576 ? (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) : (b / 1024).toFixed(0) }
  function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(1) + "T" : Math.round(b / 1e9) + "G" }
  function unit(b) { return b >= 1048576 ? "M" : "K" }
  Process {
    id: lsblkP; command: ["lsblk", "-bnPo", "NAME,TYPE,SIZE,FSUSED,PKNAME"]
    stdout: StdioCollector { onStreamFinished: {
      const d = {}, order = [];
      for (const l of text.split("\n")) {
        const m = {}, re = /(\w+)="([^"]*)"/g; let x; while ((x = re.exec(l)) !== null) m[x[1]] = x[2];
        if (m.TYPE === "disk" && !/^(loop|zram|sr)/.test(m.NAME)) { d[m.NAME] = { n: m.NAME, size: Number(m.SIZE), used: 0 }; order.push(m.NAME) }
        else if (m.TYPE === "part" && d[m.PKNAME] && m.FSUSED) d[m.PKNAME].used += Number(m.FSUSED);
      }
      p.disks = order.map(k => d[k]);
    } }
  }
  FileView {
    id: ioF; path: "/proc/diskstats"; printErrors: false
    onLoaded: {
      const now = {}, r = {};
      for (const l of text().split("\n")) { const m = l.trim().split(/\s+/); if (m.length > 9) now[m[2]] = [Number(m[5]) * 512, Number(m[9]) * 512] }
      for (const k in now) if (p.lastIo[k]) r[k] = { r: Math.max(0, now[k][0] - p.lastIo[k][0]), w: Math.max(0, now[k][1] - p.lastIo[k][1]) };
      p.lastIo = now; p.rates = r;
    }
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: ioF.reload() }
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: lsblkP.running = true }
  Repeater {
    model: p.disks.length   // a count: delegates stay, numbers change
    RowLayout {
      required property int index
      readonly property var d: p.disks[index] || ({ n: "", size: 1, used: 0 })
      readonly property var io: p.rates[d.n] || ({ r: 0, w: 0 })
      Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 8
      Cap { text: d.n.replace(/n1$/, ""); color: Theme.text; Layout.preferredWidth: Math.round(44 * Theme.scale) }
      Item {
        Layout.fillWidth: true; implicitHeight: 5
        DotMeter { anchors.verticalCenter: parent.verticalCenter; fit: parent.width; dotSize: 3; gap: 2; value: d.size > 0 ? d.used / d.size : 0; hot: 0.9; hotColor: Theme.red }
      }
      Text { text: p.gb(d.used) + "/" + p.gb(d.size); color: d.size > 0 && d.used / d.size > 0.9 ? Theme.red : Theme.dim; horizontalAlignment: Text.AlignRight
             Layout.preferredWidth: Math.round(62 * Theme.scale); font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale) }
      Row {   // activity: R / W light up while the disk moves data
        spacing: 6
        Repeater {
          model: [{ k: "R", b: io.r }, { k: "W", b: io.w }]
          Row {
            required property var modelData
            spacing: 3; width: Math.round(46 * Theme.scale)
            Rectangle { width: 4; height: 4; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.text; opacity: modelData.b > 0 ? 1 : 0.16 }
            Cap { text: modelData.k; width: Math.round(8 * Theme.scale) }
            Text { text: p.rate(modelData.b) + p.unit(modelData.b); color: modelData.b > 0 ? Theme.text : Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
          }
        }
      }
    }
  }
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
  StepSlider {   // power mode (power-profiles-daemon); the desktop has no Auto: it would only mean Balanced
    Layout.fillWidth: true
    stops: [["power saver", "Saver"], ["balanced", "Balanced"], ["performance", "Perf"]]
    current: Session.profile === "auto" ? "balanced" : Session.profile
    onPicked: id => Session.setProfile(id)
  }
}
