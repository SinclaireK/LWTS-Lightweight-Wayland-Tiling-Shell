// Default output / input (Pipewire): volume, mute. The only place that changes them.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.core

Singleton {
  id: root
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: [root.sink, root.source] }

  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property bool micMuted: source && source.audio ? source.audio.muted : false
  readonly property string icon: muted ? "speaker-slash" : volume < 0.01 ? "speaker-none"
                                 : volume < 0.5 ? "speaker-low" : "speaker-high"

  // settings_spec 4.2: overdrive allows up to 150% when enabled, plain 100% otherwise
  function setVolume(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(Prefs.get("audio_overdrive", false) ? 1.5 : 1, v)) }
  function step(d) { setVolume(Math.round((volume + d) * 20) / 20) }
  function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
  function toggleMic() { if (source && source.audio) source.audio.muted = !source.audio.muted }
  readonly property real micVolume: source && source.audio ? source.audio.volume : 0
  function setMicVolume(v) { if (source && source.audio) source.audio.volume = Math.max(0, Math.min(1, v)) }
  // device switching (launcher sound / mic rows): real devices only, not hidden ones (Settings -> Sound), not app streams / EasyEffects
  function real(n) { const nm = n.name || ""; return !n.isStream && !!n.audio && !nm.startsWith("easyeffects") && !nm.includes(".monitor") && !(Prefs.get("audio_hidden", []) || []).includes(nm) }
  readonly property var outs: Pipewire.nodes.values.filter(n => n.isSink && real(n))
  readonly property var ins: Pipewire.nodes.values.filter(n => !n.isSink && real(n))
  function shortName(n) { if (!n) return ""; const d = n.nickname || n.description || n.name || ""; const m = d.match(/\[([^\]]+)\]\s*$/); return m ? m[1] : d.split(" ").slice(0, 2).join(" ") }
  function cycle(list, cur, d) { if (list.length < 2) return null; const i = list.findIndex(n => cur && n.name === cur.name); return list[(i + d + list.length) % list.length] }
  function nextOut(d) { const n = cycle(outs, sink, d); if (n) Pipewire.preferredDefaultAudioSink = n }
  function nextIn(d) { const n = cycle(ins, source, d); if (n) Pipewire.preferredDefaultAudioSource = n }
  function micStep(d) { setMicVolume(Math.round((micVolume + d) * 20) / 20) }
}
