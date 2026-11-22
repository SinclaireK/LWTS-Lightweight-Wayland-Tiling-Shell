// What the OSD plate shows (overlays/Osd.qml): icon + track + percent for volume / brightness,
// icon + text for mute, mic, layout, Caps Lock. No slider thumb.
// A change while it is out (Caps on -> off, layout, mute, another kind) fades the old content out and the new in;
// the level and percent stay live (no fade while the volume moves), the plate follows the width smoothly.
import QtQuick
import qs.core
import qs.services

Row {
  id: c
  // live state, read straight from the sources in one call (bindings between properties update in no fixed order)
  function now() {
    const k = OsdState.kind;
    return {
      kind: k,
      level: (k === "volume" && !Audio.muted) || k === "brightness" || (k === "micvol" && !Audio.micMuted),
      off: (k === "volume" && Audio.muted) || ((k === "mic" || k === "micvol") && Audio.micMuted),
      icon: ({ volume: Audio.icon, brightness: "sun", mic: Audio.micMuted ? "microphone-slash" : "microphone", micvol: Audio.micMuted ? "microphone-slash" : "microphone",
               layout: "keyboard", caps: "arrow-fat-line-up" })[k] || "",
      label: k === "volume" ? "Mute" : k === "mic" || k === "micvol" ? (Audio.micMuted ? "Mic off" : "Mic on")
           : k === "caps" ? (OsdState.caps ? "Caps Lock on" : "Caps Lock off") : Keyboard.name,
      next: k === "layout" ? Keyboard.next : ""
    };
  }
  // a level kind keeps its key while the value moves; a text kind changes it with every new text
  readonly property string key: { const n = now(); return n.level ? n.kind : [n.kind, n.off, n.icon, n.label, n.next].join("|") }

  // what is drawn: copied from the live state at once, or between fade-out and fade-in
  property string kind; property bool level; property bool off; property string icon; property string label; property string next
  function apply() { const n = now(); kind = n.kind; level = n.level; off = n.off; icon = n.icon; label = n.label; next = n.next }
  Component.onCompleted: apply()
  onKeyChanged: {
    if (!OsdState.shown || Motion.duration === 0) { swap.stop(); opacity = 1; apply() }
    else swap.restart()
  }
  readonly property string liveIcon: Audio.icon
  onLiveIconChanged: if (level && kind === "volume") icon = Audio.icon   // speaker low / high while the volume moves
  SequentialAnimation {
    id: swap
    NumberAnimation { target: c; property: "opacity"; to: 0; duration: Motion.fit(Motion.fast * Motion.exitRatio); easing.type: Motion.type; easing.bezierCurve: Motion.exitCurve }
    ScriptAction { script: c.apply() }
    NumberAnimation { target: c; property: "opacity"; to: 1; duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve }
  }

  readonly property real value: kind === "brightness" ? OsdState.brightness : kind === "micvol" ? Audio.micVolume : Math.min(1, Audio.volume / (Prefs.get("audio_overdrive", false) ? 1.5 : 1))
  spacing: 8
  height: Prefs.barHeight

  component Label: Text {
    anchors.verticalCenter: parent.verticalCenter
    font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Theme.barPx - 2   // Nothing: mono caps
    color: c.off ? Theme.red : Theme.text
  }

  Icon { anchors.verticalCenter: parent.verticalCenter; fill: true; color: c.off ? Theme.red : Theme.text; name: c.icon }
  DotMeter {   // Nothing style: 20 dots instead of the 120px track; the live value, no fade while the volume moves
    visible: c.level
    anchors.verticalCenter: parent.verticalCenter
    value: Math.max(0, Math.min(1, c.value))
    hot: c.kind === "volume" && Prefs.get("audio_overdrive", false) ? 1 / 1.5 : 2   // overdrive: dots past 100% volume turn to the accent
  }
  UiNum {   // dot-matrix level number
    visible: c.level; width: 30
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    font.pixelSize: Math.round(Theme.barPx * 1.3)
    text: Math.round((c.kind === "brightness" ? OsdState.brightness : c.kind === "micvol" ? Audio.micVolume : Audio.volume) * 100)
  }
  Label { visible: !c.level; text: c.label }
  Label {   // layout: what comes next
    visible: c.next !== ""
    text: "⇄ " + c.next; color: Theme.dim; font.pixelSize: Theme.barPx - 3; font.weight: Font.Normal
  }
}
