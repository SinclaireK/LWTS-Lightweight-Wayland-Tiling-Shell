import QtQuick
import Quickshell
QtObject {
  property var defs: ({
    notes: { icon: "note", label: () => "Notes", on: () => false,
             act: () => Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "notes", "toggle"]) }
  })
}
