// Lock screen state. The screens themselves are overlays/LockScreen.qml (ext-session-lock: while locked the compositor shows
// only these surfaces; if the shell dies the screen STAYS locked - recover from a TTY: `pkill quickshell`, start the shell again).
// Anything that wants a lock calls Lock.lock(): the power menu, idle, a bind (`qs ipc call lock lock`), before suspend.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
  id: root
  property bool want: false         // LockScreen follows this
  readonly property real anim: ({ fast: 0.7, normal: 1, calm: 1.4 })[Prefs.get("lock_anim", "normal")] || 1   // Settings -> Lock screen -> Animation: scales every lock timing
  property bool veil: false         // after a password unlock: a blurred veil (overlays/LockFade.qml) fades out over the returning windows
  Timer { running: root.veil; interval: 3000; onTriggered: root.veil = false }   // safety: never leave the veil up
  // ---- the lock's pictures: the wallpaper cut to each screen and a pre-blurred copy, made in the background (bash + ffmpeg, once per
  // wallpaper / blur level / screen size, ~0.7 s at low priority; a check of an existing cache is ~25 ms). The lock then shows two small jpegs:
  // no 6016x6016 decode, no blur shader at lock time. Without a cache (first seconds, videos) the old live path is the fallback.
  readonly property string blurLvl: Prefs.transparency === "solid" || Theme.game ? "off" : (["light", "normal", "strong"].includes(Prefs.get("blur", "normal")) ? Prefs.get("blur", "normal") : "normal")
  readonly property real blurShrink: blurLvl === "off" ? 1 : blurLvl === "strong" ? 4 : blurLvl === "light" ? 1.5 : 2.5   // live fallback only
  readonly property string wallUrl: Wallpaper.source !== "" && !Wallpaper.isVideo ? "file://" + Wallpaper.source : ""
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/lwts/lock"
  property var pics: ({})   // screen name -> cache key
  function sharpUrl(name) { const k = pics[name]; return k ? "file://" + cacheDir + "/" + name + "-" + k + "-sharp.jpg" : wallUrl }
  function blurUrl(name) { const k = pics[name]; return !k ? "" : "file://" + cacheDir + "/" + name + "-" + k + (blurLvl === "off" ? "-sharp.jpg" : "-blur.jpg") }
  readonly property string picKey: wallUrl + "|" + Wallpaper.rev + "|" + blurLvl + "|" + Quickshell.screens.map(sc => sc.name + sc.width + "x" + sc.height).join(",")
  onPicKeyChanged: picTimer.restart()
  Component.onCompleted: picTimer.start()
  Timer { id: picTimer; interval: 700; onTriggered: { if (root.wallUrl === "") { root.pics = ({}); return } gen.command = ["bash", "-c", root.picScript, "bash", Wallpaper.source, root.blurLvl].concat(Quickshell.screens.map(sc => sc.name + ":" + Math.round(sc.width * sc.devicePixelRatio) + ":" + Math.round(sc.height * sc.devicePixelRatio))); gen.running = true } }
  Process {
    id: gen
    stdout: StdioCollector { onStreamFinished: { const m = ({}); for (const l of text.split("\n")) { const p = l.trim().split(" "); if (p.length === 2) m[p[0]] = p[1] } root.pics = m } }
  }
  readonly property string picScript: `
src=$1; lvl=$2; shift 2
d=$HOME/.cache/lwts/lock; mkdir -p "$d"
st=$(stat -c '%Y-%s' "$src") || exit 1
for spec in "$@"; do
  IFS=: read -r name w h <<< "$spec"
  key=$(printf '%s' "$src|$st|$w|$h|$lvl" | md5sum | cut -c1-12)
  s="$d/$name-$key-sharp.jpg"; b="$d/$name-$key-blur.jpg"
  if [ ! -f "$s" ]; then nice -n 19 ffmpeg -v error -y -i "$src" -vf "scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h" -q:v 3 "$s.tmp.jpg" && mv "$s.tmp.jpg" "$s" || exit 1; fi
  if [ "$lvl" != off ] && [ ! -f "$b" ]; then
    case $lvl in light) k=1.5; sg=6;; strong) k=4; sg=12;; *) k=2.5; sg=10;; esac
    nice -n 19 ffmpeg -v error -y -i "$s" -vf "scale=trunc(iw/$k/2)*2:trunc(ih/$k/2)*2,gblur=sigma=$sg,eq=brightness=-0.06:contrast=0.92:saturation=0.85,scale=$w:$h:flags=bicubic" -q:v 3 "$b.tmp.jpg" && mv "$b.tmp.jpg" "$b" || exit 1
  fi
  find "$d" -name "$name-*" ! -name "$name-$key-*" -delete
  echo "$name $key"
done`

  // ---- one motion, both ways, all in parallel: a lock request starts the session lock at once AND plays the opening on an overlay above the
  // windows (overlays/LockFade.qml: the blurred wallpaper fades in while the plate grows out of the bar). The compositor shows the normal
  // scene until the lock surface has drawn (~0.4 s), so the overlay stays until both are done: its animation and the surface's first frames,
  // which start as the overlay's last frame. The unlock is the same stage played back.
  property bool locked: false       // LockScreen reports back: the compositor confirmed the lock
  property bool pre: false          // the opening overlay is up
  property bool animDone: false     // the opening reached its end
  property bool surfaceDrew: false  // the lock surface drew its first frames
  // ONE progress for the opening, read by the overlay's stage and by the real lock surface's stage alike (LockStage `driven`): whichever the
  // compositor shows, the plate and the wallpaper are at the same point. Started by whichever of them drew its first frame first.
  property real openK: 0            // the plate (bar -> screen)
  property real openF: 0            // the wallpaper fade
  Behavior on openK { id: bk; SequentialAnimation {   // the fade leads: the plate starts three frames after it
    PauseAnimation { duration: Motion.off ? 0 : Motion.frame * 3 * Motion.slowmo }
    NumberAnimation { duration: Motion.fit(Motion.slow * root.anim); easing.type: Motion.type; easing.bezierCurve: [0.3, 0.1, 0.2, 1, 1, 1] }
  } }
  Behavior on openF { id: bf; NumberAnimation { duration: Motion.fit(240 * root.anim * Motion.slowmo); easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
  // the session lock engages when the overlay's opening has ended: creating its surfaces blocks the UI thread for ~0.5 s (a frozen fade otherwise) and the first surface frame cuts the windows off at once
  onOpenKChanged: if (openK === 1 && pre) { animDone = true; if (surfaceDrew) pre = false; else want = true }
  function startOpening() { openK = 1; openF = 1 }
  function lock(instant) {   // instant (boot, sleep, screen off): nobody watches the opening, the session lock engages at once
    if (want || pre) return
    animDone = false; surfaceDrew = false
    bk.enabled = false; bf.enabled = false; openK = 0; openF = 0; bk.enabled = true; bf.enabled = true
    if (Motion.off || instant === true) { openK = openF = 1; want = true } else pre = true
  }
  function surfaceReady() { surfaceDrew = true; if (animDone || !pre) pre = false }
  Timer { running: root.pre; interval: 1500 + 1000 * root.anim * Motion.slowmo; onTriggered: { root.pre = false; root.startOpening(); root.want = true } }   // never leave the overlay up
  function unlocked() { want = false; locked = false; pre = false }

  IpcHandler {
    target: "lock"
    function lock(): void { root.lock() }
    function status(): string { return root.locked ? "locked" : "unlocked" }
  }
}
