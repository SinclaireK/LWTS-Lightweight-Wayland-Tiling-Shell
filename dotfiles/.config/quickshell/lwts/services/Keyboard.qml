// Keyboard layout: niri event stream (Compositor), no polling. name: "English" (bar), current: "EN" (OSD).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property string name: ""          // English
  property string current: ""       // EN
  property var codes: []            // ["EN", "RU"] in switch order
  readonly property string next: codes.length > 1 ? codes[(codes.indexOf(current) + 1) % codes.length] : ""

  function code(s) {   // "English (US)" | "us" -> "EN"
    const m = { english: "EN", us: "EN", russian: "RU", ru: "RU", ukrainian: "UA", ua: "UA" };
    const k = s.toLowerCase().split(/[\s(]/)[0];
    return m[k] || k.slice(0, 2).toUpperCase();
  }
  function setActive(keymap) { name = keymap.replace(/ \(.*/, ""); current = code(keymap) }
  function switchNext() { Compositor.switchLayout() }

  Connections {   // niri sends the list and every switch over the event stream; nothing is polled
    target: Compositor
    function onLayoutNamesChanged() { root.codes = Compositor.layoutNames.map(root.code) }
    function onLayoutNameChanged() { if (Compositor.layoutName !== "") root.setActive(Compositor.layoutName) }
  }
  Component.onCompleted: { codes = Compositor.layoutNames.map(code); if (Compositor.layoutName !== "") setActive(Compositor.layoutName) }
}
