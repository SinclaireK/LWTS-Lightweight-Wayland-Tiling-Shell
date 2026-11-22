import QtQuick
import Quickshell
QtObject {
  property var defs: ({
    clip: { icon: "clipboard-text", label: () => "Clipboard", on: () => false,
            act: () => Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "clip", "toggle"]) }
  })
}
