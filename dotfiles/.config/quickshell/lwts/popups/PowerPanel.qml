// Power (bar: the battery, System drop category "power"): charge, state, time left, and the power mode as a stepped slider (Session.profiles;
// "auto" is its own row; the Quick settings tile only cycles it). Laptop only: SystemPanel shows the tab when a laptop battery exists.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
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
  readonly property var bat: Session.bat
  readonly property bool charging: !!bat && bat.state === UPowerDeviceState.Charging
  readonly property string remaining: {   // "3 h 12 min left" / "45 min to full"
    if (!bat) return "";
    const s = charging ? bat.timeToFull : bat.state === UPowerDeviceState.Discharging ? bat.timeToEmpty : 0;
    if (!s || s <= 0) return "";
    const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
    return (h > 0 ? h + " h " : "") + m + " min" + (charging ? " to full" : " left");
  }
  readonly property string effective: Session.acLaptop ? "performance" : "balanced"   // what "auto" applies right now
  readonly property bool auto: Session.profile === "auto"
  RowLayout {   // hero: the charge in dot-matrix numerals, state and time beside it
    Layout.fillWidth: true; spacing: 6
    UiNum { text: p.bat ? Math.round(p.bat.percentage * 100) : ""; size: Math.round(30 * Theme.scale); color: p.charging ? Theme.accent : Theme.text }
    Text { text: "%"; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale); Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
    Item { Layout.fillWidth: true }
    Column {
      Layout.alignment: Qt.AlignVCenter
      Text { anchors.right: parent.right; color: Theme.text; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
             text: !p.bat ? "" : p.charging ? "Charging" : p.bat.state === UPowerDeviceState.FullyCharged ? "Full" : "On battery" }
      Text { anchors.right: parent.right; color: Theme.dim; font.pixelSize: Math.round(11 * Theme.scale); text: p.remaining }
    }
  }
  readonly property real health: designWh > 0 ? Math.min(1, fullWh / designWh) : 1
  Item {   // the battery as a track: full width = the design capacity; the charge filled, the worn-out part as dots; two ticks = the charge range
    id: track
    visible: p.designWh > 0 && !!p.bat
    Layout.fillWidth: true; implicitHeight: 24
    property bool focused: false   // panel row: ↑ ↓ pick it (panelkeys), Enter / Space switch the handle (stop / start), ← → move it by 5
    property string handle: "stop"
    signal act()
    function nudge(d) { const v = (handle === "stop" ? p.stopShown : p.startShown) + (d > 0 ? 5 : -5); handle === "stop" ? p.setRange(p.startShown, v) : p.setRange(v, p.stopShown) }
    Component.onCompleted: act.connect(() => handle = handle === "stop" ? "start" : "stop")
    readonly property real level: p.bat ? p.bat.percentage : 0
    property real dragVal: -1   // while a tick is dragged
    property string dragging: ""
    readonly property real stopV: dragging === "stop" ? dragVal : p.stopShown
    readonly property real startV: dragging === "start" ? dragVal : p.startShown
    readonly property real inner: width - 8   // the track itself, 4 px of air each side
    function xOfPct(v) { return 4 + inner * v / 100 * p.health }
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover; opacity: track.focused ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Motion.fast } } }
    Rectangle { x: 4; y: 9; width: track.inner; height: 6; radius: 2; color: Theme.line }
    Rectangle {
      x: 4; y: 9; height: 6; radius: 2; color: p.charging ? Theme.accent : p.bat && p.bat.percentage <= 0.15 && !p.charging ? Theme.red : Theme.text
      width: track.inner * track.level * p.health
      Behavior on width { enabled: !Motion.off; NumberAnimation { duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
    }
    Repeater {   // worn-out capacity: dots in the right end
      model: Math.max(0, Math.floor(track.inner * (1 - p.health) / 4))
      Rectangle { required property int index; x: 4 + track.inner - 3 - index * 4; y: 11; width: 2; height: 2; radius: 1; color: Theme.dim }
    }
    Repeater {   // the two handles: start (shorter, below) and stop
      model: ["start", "stop"]
      Rectangle {
        required property string modelData
        readonly property bool isStop: modelData === "stop"
        readonly property bool on: track.dragging === modelData || (track.focused && track.handle === modelData) || hit.hoverNear === modelData
        x: track.xOfPct(isStop ? track.stopV : track.startV) - 1; y: isStop ? 4 : 7; width: 2; height: isStop ? 16 : 10; radius: 1
        color: Theme.text; opacity: on ? 1 : 0.6
        Behavior on x { enabled: track.dragging === "" && !Motion.off; NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
      }
    }
    MouseArea {   // grab the nearest tick and drag; the range is sent on release (no wheel: scrolling past must not change a limit)
      id: hit
      anchors.fill: parent; hoverEnabled: true
      property string hoverNear: ""
      function nearest(mx) {
        const ds = Math.abs(mx - track.xOfPct(track.stopV)), dt = Math.abs(mx - track.xOfPct(track.startV));
        return Math.min(ds, dt) < 12 ? (ds <= dt ? "stop" : "start") : "";
      }
      cursorShape: track.dragging !== "" || hoverNear !== "" ? Qt.SizeHorCursor : Qt.ArrowCursor
      function valAt(mx, which) {
        const v = Math.round((mx - 4) / (track.inner * p.health) * 100 / 5) * 5;
        return which === "stop" ? Math.max(Math.max(50, p.startShown + 5), Math.min(100, v)) : Math.max(5, Math.min(p.stopShown - 5, v));
      }
      onPositionChanged: m => { if (track.dragging !== "") track.dragVal = valAt(m.x, track.dragging); else hoverNear = nearest(m.x) }
      onExited: hoverNear = ""
      onPressed: m => { const w = nearest(m.x); if (w === "") { m.accepted = false; return } track.handle = w; track.dragging = w; track.dragVal = valAt(m.x, w) }
      onReleased: { if (track.dragging !== "") { track.dragging === "stop" ? p.setRange(p.startShown, track.dragVal) : p.setRange(track.dragVal, p.stopShown); track.dragging = ""; track.dragVal = -1 } }
      onCanceled: { track.dragging = ""; track.dragVal = -1 }
    }
  }
  RowLayout {   // the battery's resource, one quiet line under the track
    visible: p.designWh > 0
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 14
    Repeater {
      model: 3
      Row {
        required property int index
        readonly property var it: [{ k: "Health", v: Math.round(p.health * 100) + "%" }, { k: "Cycles", v: p.cycles > 0 ? String(p.cycles) : "-" },
                                   { k: "Charge", v: track.stopV >= 100 ? "Off" : Math.round(track.startV) + "–" + Math.round(track.stopV) + "%" }][index]
        spacing: 5
        Text { text: it.k; color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
        Text { text: it.v; color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
      }
    }
    Item { Layout.fillWidth: true }
  }
  StepSlider {   // power mode, the Windows way: one slider; Auto is its first stop
    Layout.fillWidth: true
    stops: [["auto", "Auto"], ["power saver", "Saver"], ["balanced", "Balanced"], ["performance", "Perf"]]
    current: Session.profile
    onPicked: id => Session.setProfile(id)
  }
  Text {   // what Auto does right now (it is the shell's rule on top of the profile: mains = Performance, battery = Balanced)
    visible: p.auto
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
    wrapMode: Text.WordWrap; color: Theme.dim; font.pixelSize: Math.round(11 * Theme.scale)
    text: "Now " + (p.effective === "performance" ? "Performance (on mains)" : "Balanced (on battery)")
  }
  // consumption details: what the battery gives / takes now, how healthy it is, the package power limits (RAPL). sysfs, no root; read every 2 s
  // only while this tab is open (the panel is loaded on demand).
  readonly property string batDir: "/sys/class/power_supply/" + (bat && bat.nativePath ? bat.nativePath : "BAT0")
  property real drawW: 0
  property real fullWh: 0
  property real designWh: 0
  property int cycles: 0
  property int chargeLimit: 0   // the stop threshold (charging ends here)
  property int chargeStart: 0   // the start threshold (charging begins below it)
  property int pendStop: -1     // a requested range not yet seen in sysfs (lwts-powerd applies it within ~2 s)
  property int pendStart: -1
  readonly property int stopShown: pendStop >= 0 ? pendStop : chargeLimit
  readonly property int startShown: pendStart >= 0 ? pendStart : (chargeStart > 0 ? chargeStart : stopShown - 5)
  function setRange(start, stop) {   // stop 50..100, start 5..stop-5, steps of 5; lwts-powerd (root) validates and applies it
    stop = Math.max(50, Math.min(100, Math.round(stop / 5) * 5));
    start = Math.max(5, Math.min(stop - 5, Math.round(start / 5) * 5));
    if (stop === stopShown && start === startShown) return;
    pendStop = stop; pendStart = start; fLimitReq.setText(start + " " + stop); pend.restart()
  }
  Timer { id: pend; interval: 7000; onTriggered: { p.pendStop = -1; p.pendStart = -1 } }   // never applied (the service is not running): show the real values again
  // live watts per domain from lwts-powerd (root sampler, /run/lwts/power); it samples only while this tab keeps touching the want file
  property var live: ({})
  readonly property bool liveOk: live.t !== undefined && Date.now() / 1000 - live.t < 30 && live.core !== undefined
  readonly property real cpuW: liveOk ? live.core : 0
  readonly property real gpuW: liveOk ? (live.uncore || 0) : 0
  readonly property real ramW: liveOk ? (live.dram || 0) : 0
  readonly property real restW: !liveOk || charging ? 0 : Math.max(0, drawW - cpuW - gpuW - ramW)   // on mains the battery figure is the charge rate, not the draw: no "rest"
  function num(fv) { return Number((fv.text() || "0").trim()) }
  FileView { id: fDraw; path: p.batDir + "/power_now"; printErrors: false; onLoaded: p.drawW = p.num(fDraw) / 1e6 }
  FileView { id: fFull; path: p.batDir + "/energy_full"; printErrors: false; onLoaded: p.fullWh = p.num(fFull) / 1e6 }
  FileView { id: fDesign; path: p.batDir + "/energy_full_design"; printErrors: false; onLoaded: p.designWh = p.num(fDesign) / 1e6 }
  FileView { id: fCycles; path: p.batDir + "/cycle_count"; printErrors: false; onLoaded: p.cycles = p.num(fCycles) }
  FileView {
    id: fLimit; path: p.batDir + "/charge_control_end_threshold"; printErrors: false
    onLoaded: { p.chargeLimit = p.num(fLimit); if (p.pendStop === p.chargeLimit && p.pendStart === p.chargeStart) { p.pendStop = -1; p.pendStart = -1; pend.stop() } }
  }
  FileView { id: fStart; path: p.batDir + "/charge_control_start_threshold"; printErrors: false; onLoaded: p.chargeStart = p.num(fStart) }
  FileView { id: fLimitReq; path: Quickshell.env("XDG_RUNTIME_DIR") + "/lwts-charge-limit"; printErrors: false }
  FileView {
    id: fLive; path: "/run/lwts/power"; printErrors: false
    onLoaded: { const o = {}; for (const l of text().split("\n")) { const m = l.match(/^(\w+)=(.+)$/); if (m) o[m[1]] = Number(m[2]) } p.live = o }
  }
  FileView { id: fWant; path: Quickshell.env("XDG_RUNTIME_DIR") + "/lwts-power-want"; printErrors: false }
  Timer {
    interval: 2000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: { fDraw.reload(); fFull.reload(); fDesign.reload(); fCycles.reload(); fLimit.reload(); fStart.reload(); fLive.reload(); fWant.setText(String(Math.floor(Date.now() / 1000))) }
  }
  component KV: RowLayout {
    property string k
    property string v
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
    Text { text: parent.k; color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
    Item { Layout.fillWidth: true }
    Text { text: parent.v; color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
  }
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 4 }
  KV { k: p.charging ? "Charging" : "Draw"; v: p.drawW > 0 ? p.drawW.toFixed(1) + " W" : "-" }
  SplitBar {   // the draw shared between the CPU cores, the GPU, the memory and the rest (display, disk, radios, conversion losses; on mains no "rest")
    visible: p.liveOk; Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
    segs: [{ w: p.cpuW, a: 1 }, { w: p.gpuW, a: 0.65 }, { w: p.ramW, a: 0.4 }, { w: p.restW, a: 0.2 }]
  }
  RowLayout {
    visible: p.liveOk; Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 12
    Repeater {
      model: 4   // a count: the delegates stay, their numbers change
      Row {
        required property int index
        readonly property var it: [{ n: "CPU", w: p.cpuW, a: 1 }, { n: "GPU", w: p.gpuW, a: 0.65 }, { n: "RAM", w: p.ramW, a: 0.4 }, { n: "Rest", w: p.restW, a: 0.2 }][index]
        visible: it.n !== "Rest" || !p.charging
        spacing: 5
        Rectangle { width: 6; height: 6; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.text; opacity: it.a }
        Text { text: it.n; color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
        Text { text: it.w.toFixed(1); color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
      }
    }
    Item { Layout.fillWidth: true }
  }
}
