// Wallpaper state and control for niri (replaces hyprpaper + next-wallpaper.sh). The single owner of "what is on the
// desktop" is theme.py: `theme.py wallpaper-set <file>` picks the recoloured copy, writes the two state files below and makes
// the theme follow it. This service only watches those files (overlays/WallpaperLayer.qml draws them) and offers set/next/prev.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  readonly property string home: Quickshell.env("HOME")
  readonly property string dir: home + "/Pictures/Wallpapers"
  property string original: ""    // the picked file
  property string shown: ""       // what is drawn: the original or its recoloured copy (video files are drawn as they are)
  property int rev: 0             // +1 on every write of the shown file: the same path may hold a re-rendered picture
  readonly property string source: shown !== "" ? shown : (Theme.data.image || "")
  readonly property bool isVideo: Modules.videoUrl !== "" && /\.(mp4|webm|mkv|mov|avi|gif)$/i.test(source)
  property bool paused: false     // set by shell.qml: game mode / locked / idle -> a video stops, nothing is decoded

  function set(path) {
    if (!path) return;
    Quickshell.execDetached(["env", "THEME_QUIET=1", "python3", home + "/.config/themes/theme.py", "wallpaper-set", path]);
  }
  // next / prev through ~/Pictures/Wallpapers (same order as the old script: sorted names), wraps around
  property int _dir: 1
  function step(d) { _dir = d; list.running = true }
  function next() { step(1) }
  function prev() { step(-1) }
  Process {
    id: list
    command: ["sh", "-c", "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' \\) | sort", "sh", root.dir]
    stdout: StdioCollector {
      onStreamFinished: {
        const files = text.split("\n").filter(x => x);
        if (!files.length) return;
        const i = files.indexOf(root.original);
        root.set(files[(i + root._dir + files.length) % files.length]);
      }
    }
  }

  // Stills are drawn by awww-daemon (a separate process, started by niri), not by the shell: the shell only tells it what to show.
  // The daemon keeps the last picture, so a shell restart needs no redraw (first call uses no transition).
  property bool _first: true
  // Debounced: at start `source` is first the theme's original (the state file is not read yet), then the shown copy; two awww calls
  // raced and the original could finish last. One call, for the latest source, 200 ms after the last change.
  function push() { pushTimer.restart() }
  Timer { id: pushTimer; interval: 200; onTriggered: root.doPush() }
  function doPush() {
    if (isVideo || source === "") return;
    const tr = _first ? "none" : "fade";
    _first = false;
    Quickshell.execDetached(["sh", "-c", "for i in 1 2 3 4 5 6 7 8; do awww img \"$1\" --transition-type \"$2\" --transition-duration 0.45 && exit; sleep 0.5; done", "sh", source, tr]);
  }
  onSourceChanged: push()
  onRevChanged: push()
  onIsVideoChanged: push()   // video off -> show the still again
  // Overview backdrop: a second awww-daemon (namespace "backdrop", niri puts it behind the workspaces). themes/backdrop.py renders the
  // theme-colour gradient picture for each output; redone when the wallpaper, the theme colours, the mode or the style change.
  readonly property var _bd: [original, Theme.c("surface", ""), Theme.c("primary", ""), Theme.c("tertiary", "#d3869b"), Theme.c("secondary", "#89b482"),
                              Theme.c("primary_container", "#504945"), Session.dark, Prefs.get("backdrop_style", "gradient")]
  on_BdChanged: bdTimer.restart()
  Timer {
    id: bdTimer
    interval: 700
    onTriggered: {
      const c = x => String(x), s = c(Theme.c("surface", "#282828"));
      const py = root.home + "/.config/themes/backdrop.py";
      if (Prefs.get("backdrop_style", "gradient") === "off") Quickshell.execDetached(["python3", py, "--off", s]);
      else if (root.original !== "") Quickshell.execDetached(["python3", py, root.original, s,
        [Theme.c("primary", "#d8a657"), Theme.c("tertiary", "#d3869b"), Theme.c("secondary", "#89b482"), Theme.c("primary_container", "#504945")].map(c).join(","), Session.dark ? "1" : "0"]);
    }
  }
  FileView {
    path: root.home + "/.local/state/lwts-wallpaper-shown"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { const t = text().trim(); if (t === root.shown) root.rev++; else root.shown = t }
  }
  FileView {
    path: root.home + "/.local/state/lwts-wallpaper"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.original = text().trim()
  }

  IpcHandler {
    target: "wallpaper"
    function set(path: string): void { root.set(path) }
    function next(): void { root.next() }
    function prev(): void { root.prev() }
    function current(): string { return root.source }
  }
}
