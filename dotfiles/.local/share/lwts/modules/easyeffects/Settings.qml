// The "EasyEffects" tab of Settings -> Sound (moved from settings/SettingsNew.qml): status, global bypass, presets.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Scope {
  id: root
  property string section: "sound"
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  property bool active: false
  property int bypass: 1
  Process { id: check; command: ["pgrep", "-x", "easyeffects"]; onExited: code => root.active = code === 0 }
  Process { id: bypassCheck; command: ["easyeffects", "-b", "3"]
            stdout: StdioCollector { onStreamFinished: { const m = this.text.match(/(\d)/); if (m) root.bypass = Number(m[1]) } } }
  Connections { target: Modules; function onOpenSectionChanged() { if (Modules.openSection === "sound") { check.running = true; bypassCheck.running = true } } }
  property var rows: [
      tab("EasyEffects"),
      header("Processing"),
      { type: "info", label: "Status", value: active ? "● Active" : "Not running" },
      choice("Apply effects", "Global bypass", [["off", "Bypass"], ["on", "Apply"]],
             () => bypass === 2 ? "on" : "off", v => { bypass = v === "on" ? 2 : 1; Quickshell.execDetached(["easyeffects", "-b", String(bypass)]) }),
      choice("Output preset", "", [["earpods", "EarPods EQ"]], () => "earpods", v => Quickshell.execDetached(["easyeffects", "-l", v])),
      choice("Input preset", "", [["voice", "Voice Stream"], ["voice-full", "Voice Full"], ["voice-eq", "Voice EQ"]],
             () => Prefs.get("ee_input_preset", "voice"), v => { Prefs.set("ee_input_preset", v); Quickshell.execDetached(["easyeffects", "-l", v]) }),
      { type: "action", label: "Open EasyEffects", desc: "", buttons: [["Open", () => Quickshell.execDetached(["easyeffects"])]] },
  ]
}
