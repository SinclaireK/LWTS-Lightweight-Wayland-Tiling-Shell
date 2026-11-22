// On-screen display state (overlays/Osd.qml): what changed and whether it is out.
// Events: volume / mute / mic (Pipewire), layout (Hyprland), brightness by ipc
// (`qs -c lwts ipc call osd brightness` from brightness.sh), Caps Lock by its LED. 1.2 s, nothing in game mode.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Singleton {
  id: root
  property string kind: ""        // volume | mic | micvol | layout | caps | brightness
  property bool shown: false
  property bool caps: false
  property real brightness: 0     // 0..1, laptop backlight
  property bool ready: false      // no OSD for the values read at startup
  signal popped()

  // niri 26.04 has no fullscreen flag in its window IPC: a focused window as big as its output is a fullscreen one
  readonly property bool fullscreenFocused: {
    const w = Compositor.focusedWindow, o = Compositor.outputs[Compositor.focusedOutput];
    const sz = w && w.layout ? w.layout.window_size : null, lg = o ? o.logical : null;
    return !!sz && !!lg && sz[0] >= lg.width && sz[1] >= lg.height;
  }
  function pop(k) {
    if (!ready || Theme.playing || fullscreenFocused) return;
    kind = k; shown = true; hide.restart(); popped();
  }
  function checkCaps() { capsFile.reload() }
  function checkBrightness() { lightProc.running = true }

  Timer { id: hide; interval: 1200; onTriggered: root.shown = false }
  Timer { interval: 1000; running: true; onTriggered: root.ready = true }
  Connections {
    target: Audio
    function onVolumeChanged() { root.pop("volume") }
    function onMutedChanged() { root.pop("volume") }
    function onMicMutedChanged() { root.pop("mic") }
    function onMicVolumeChanged() { root.pop("micvol") }
  }
  Connections { target: Keyboard; function onCurrentChanged() { root.pop("layout") } }

  // niri's IPC has no caps state and a Caps_Lock bind would eat the key (games never saw it): read the keyboard
  // LED in-process. sysfs sends no inotify, so a light 250 ms re-read; stopped in game mode (no OSD there anyway)
  property string capsLed: ""
  property string capsPath: ""
  Process {   // the LED name (input2::capslock) differs per machine: resolve it once
    running: true
    command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null | sort -V | head -1"]
    stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) root.capsPath = p + "/brightness" } }
  }
  FileView {
    id: capsFile
    path: root.capsPath
    onLoaded: {
      const v = text().trim();
      if (v === "" || v === root.capsLed) return;
      const first = root.capsLed === "";   // remember the LED at startup, no OSD
      root.capsLed = v; root.caps = v !== "0";
      if (!first) root.pop("caps");
    }
  }
  Timer { interval: 250; repeat: true; running: root.capsPath !== "" && !Theme.playing; onTriggered: capsFile.reload() }
  Process {   // brightnessctl -m: name,class,current,percent%,max - only a real backlight (no-op on the desktop)
    id: lightProc
    command: ["brightnessctl", "-m", "-c", "backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = parseInt((text.split(",")[3] || ""));
        if (!isNaN(p)) { root.brightness = p / 100; root.pop("brightness") }
      }
    }
  }
}
