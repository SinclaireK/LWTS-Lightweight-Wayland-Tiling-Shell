// Calculator for the launcher: qalc, after a short pause in typing, only when the text has a digit.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property string input: ""
  property string result: ""   // "" = nothing to show
  onInputChanged: delay.restart()
  function copy() { if (result) Quickshell.execDetached(["wl-copy", result]) }

  Timer {
    id: delay; interval: 120
    onTriggered: {
      const q = root.input.trim();
      if (/\d/.test(q)) { proc.command = ["qalc", "-t", q]; proc.running = true } else root.result = "";
    }
  }
  Process {
    id: proc
    stdout: StdioCollector {
      onStreamFinished: {
        const r = this.text.trim();
        root.result = r && r !== root.input.trim() && !r.startsWith("error") ? r : "";
      }
    }
  }
}
