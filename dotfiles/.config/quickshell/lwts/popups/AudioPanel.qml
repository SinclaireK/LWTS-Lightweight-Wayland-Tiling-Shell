// Sound (bar: sound icon), panel-style: hero volume numeral + dotted track, mic, apps (one line each), devices folded. Rows: ←→ volume, Enter mute.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
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
  function real(n) { return !(n.name || "").startsWith("easyeffects_") }   // settings_spec 4.4: never a selectable device
  readonly property var outs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio && p.real(n))
  readonly property var ins: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio && !(n.name || "").includes(".monitor") && p.real(n))
  readonly property var apps: Pipewire.nodes.values.filter(n => n.isStream && n.isSink)
  PwObjectTracker { objects: p.outs.concat(p.ins, p.apps) }
  function label(n) { return n.description || n.nickname || n.name }

  component Cap: Text { color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  component VolRow: Item {
    id: vr
    property var node
    property string icon: "speaker-high"
    property string label: ""    // a short name left of the track (apps, mic)
    property bool pct: true
    readonly property int nameW: Math.round(84 * Theme.scale)
    readonly property int pctW: 36
    readonly property real maxv: Prefs.get("audio_overdrive", false) ? 1.5 : 1   // one switch (Boost) for every row: track scale and ceiling; past 100% the dots are red
    readonly property real limit: maxv
    property bool focused: false
    signal act()   // keyboard Enter: mute / unmute
    readonly property bool muted: !!node && !!node.audio && node.audio.muted
    function nudge(d) { if (node && node.audio) node.audio.volume = Math.max(0, Math.min(limit, node.audio.volume + d)) }
    onAct: if (node && node.audio) node.audio.muted = !node.audio.muted
    Layout.fillWidth: true
    implicitHeight: rl.implicitHeight + 2
    Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover; visible: vr.focused }
    RowLayout {
      id: rl
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 4; rightMargin: 4 }
      spacing: 8
      Cap {   // one grid for every row: name (click = mute) | track | percent
        text: vr.muted ? "Muted" : vr.label; elide: Text.ElideRight; Layout.preferredWidth: vr.nameW
        color: vr.muted ? Theme.red : Theme.dim
        MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: vr.act() }
      }
      Slider { Layout.fillWidth: true; maxv: vr.maxv; wave: true; opacity: vr.muted ? 0.35 : 1; value: vr.node && vr.node.audio ? vr.node.audio.volume : 0
               onMoved: v => { if (vr.node && vr.node.audio) vr.node.audio.volume = Math.min(vr.limit, v) } }
      Text { opacity: vr.pct ? 1 : 0; text: vr.node && vr.node.audio ? Math.round(vr.node.audio.volume * 100) + "%" : ""; color: Theme.dim
             Layout.preferredWidth: vr.pctW; horizontalAlignment: Text.AlignRight; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
    }
  }
  function short(n) {   // "Navi 21/23 HDMI/DP Audio Controller Digital Stereo (HDMI)" -> the first two words of what matters
    const t = label(n).replace(/\s*(Digital|Analog)?\s*Stereo.*$/i, "").replace(/\s*Audio Controller/i, "");
    return t;
  }
  function kind(n) {   // a glyph by what the device is
    const t = (label(n) + " " + (n.name || "")).toLowerCase();
    if (/hdmi|displayport|\bdp\b|monitor/.test(t)) return "monitor";
    if (/head(set|phone)|bluez|airpods|buds/.test(t)) return "headphones";
    if (/usb/.test(t)) return "usb";
    return n.isSink ? "speaker-high" : "microphone";
  }
  readonly property int shownApps: 4

  // ---- hero: the volume of the default output, big (digits roll to the new value); BOOST lifts the ceiling to 150%; the device on the right
  readonly property bool boost: Prefs.get("audio_overdrive", false)
  readonly property bool sinkMuted: !!Audio.sink && !!Audio.sink.audio && Audio.sink.audio.muted
  function setBoost(on) {   // off: everything above 100% comes back to 100%
    Prefs.set("audio_overdrive", on);
    if (!on) for (const n of [Audio.sink, Audio.source].concat(p.apps)) if (n && n.audio && n.audio.volume > 1) n.audio.volume = 1
  }
  RowLayout {
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 6
    UiNum {
      id: big
      property real shown: Audio.sink && Audio.sink.audio ? Audio.sink.audio.volume * 100 : 0
      Behavior on shown { NumberAnimation { duration: Motion.off ? 0 : 220; easing.type: Easing.OutCubic } }
      size: Math.round(32 * Theme.scale); text: Audio.sink && Audio.sink.audio ? Math.round(shown) : "–"
      color: shown > 100.5 ? Theme.red : Theme.text; opacity: p.sinkMuted ? 0.35 : 1
    }
    Cap { text: p.sinkMuted ? "Muted" : "%"; color: p.sinkMuted ? Theme.red : Theme.dim; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
    UiButton { text: "Boost"; on: p.boost; padX: 10; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 4; onClicked: p.setBoost(!p.boost) }
    Item { Layout.fillWidth: true }
    Cap { text: Audio.sink ? p.short(Audio.sink) : "No output"; elide: Text.ElideRight; Layout.maximumWidth: Math.round(150 * Theme.scale); Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 8 }
  }
  VolRow { node: Audio.sink; label: "Out" }
  PwNodePeakMonitor { id: peak; node: Audio.sink; enabled: !!Audio.sink }
  Item {   // live level of what is playing: a thin dotted line under the track, steps like a dot-matrix display
    Layout.fillWidth: true; Layout.leftMargin: 4 + 8 + Math.round(84 * Theme.scale); Layout.rightMargin: 4 + 8 + 36; implicitHeight: 4; Layout.topMargin: -4
    DotMeter { fit: parent.width; dotSize: 2; gap: 3; value: Math.min(1, peak.peak * 1.4); litColor: Theme.dim; hot: 0.85; hotColor: Theme.red }
  }
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
  VolRow { node: Audio.source; label: "Mic" }
  Repeater {
    model: p.apps.slice(0, p.shownApps)
    VolRow { required property var modelData; node: modelData; label: modelData.properties["application.name"] || modelData.name }   // apps may need > 100%
  }
  Cap { visible: p.apps.length > p.shownApps; text: "+" + (p.apps.length - p.shownApps) + " more apps"; Layout.leftMargin: 4 }

  function pick(list, cur, d, set) {   // the device d steps away in a list, wrapping
    if (list.length < 2) return;
    const i = Math.max(0, list.indexOf(cur));
    set(list[(i + d + list.length) % list.length]);
  }
  property bool devs: false
  readonly property bool switchable: outs.length > 1 || ins.length > 1   // nothing to pick with one device each: the block is not shown at all
  function soundSettings() { p.closeMe(); Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "settingsId", "sound"]) }
  UiDotLine { Layout.fillWidth: true; Layout.topMargin: 2 }
  UiFoldRow { visible: p.switchable; text: "Devices"; glyphs: (p.outs.length > 1 ? [p.kind(Audio.sink || p.outs[0])] : []).concat(p.ins.length > 1 ? [p.kind(Audio.source || p.ins[0])] : []); open: p.devs; onAct: p.devs = !p.devs }
  ColumnLayout {
    id: devBox
    visible: p.switchable && (p.devs || Layout.preferredHeight > 0.5); clip: true; Layout.fillWidth: true; spacing: 6
    Layout.preferredHeight: p.devs ? implicitHeight : 0
    Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.off ? 0 : Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
    UiCycleRow {
      visible: p.outs.length > 1
      caption: "Output"; icon: p.outs.length ? p.kind(Audio.sink || p.outs[0]) : ""; text: Audio.sink ? p.short(Audio.sink) : "—"
      count: p.outs.length; index: Math.max(0, p.outs.indexOf(Audio.sink))
      onStep: d => p.pick(p.outs, Audio.sink, d, n => Pipewire.preferredDefaultAudioSink = n)
    }
    UiCycleRow {
      visible: p.ins.length > 1
      caption: "Input"; icon: p.ins.length ? p.kind(Audio.source || p.ins[0]) : ""; text: Audio.source ? p.short(Audio.source) : "—"
      count: p.ins.length; index: Math.max(0, p.ins.indexOf(Audio.source))
      onStep: d => p.pick(p.ins, Audio.source, d, n => Pipewire.preferredDefaultAudioSource = n)
    }
    UiFoldRow { text: "All sound settings"; glyph: "arrow-up-right"; onAct: p.soundSettings() }
  }
  UiDotLine { visible: !p.switchable; Layout.fillWidth: true; Layout.topMargin: 2 }
  UiFoldRow { visible: !p.switchable; text: "All sound settings"; glyph: "arrow-up-right"; onAct: p.soundSettings() }
}
