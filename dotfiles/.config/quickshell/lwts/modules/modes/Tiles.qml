import QtQuick
import qs.services
QtObject {
  property var defs: ({
    focus:  { icon: "target", label: () => "Focus", on: () => Modes.mode === "focus", act: () => Modes.toggle("focus"),
              status: () => Modes.mode === "focus" ? (Modes.phase === "work" ? "Work " : "Break ") + Modes.leftText : "",
              progress: () => Modes.progress,
              face: () => Modes.mode === "focus" ? { status: Modes.phase === "work" ? "Work" : "Break", hero: Modes.leftText } : { status: Modes.workMin + " / " + Modes.breakMin + " min" } },
    sleep:  { icon: "moon", label: () => "Sleep", on: () => Modes.mode === "sleep", act: () => Modes.toggle("sleep") },
    stream: { icon: "broadcast", label: () => "Stream", on: () => Modes.mode === "stream", act: () => Modes.toggle("stream") },
  })
}
