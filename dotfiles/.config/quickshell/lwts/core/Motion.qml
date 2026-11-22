// One motion for the whole shell, tuned to the screen, not configurable (Settings -> Look -> Motion: on | off; off also in Lite).
// >= 90 Hz: a soft spring with a small overshoot. 60 Hz: an overshoot shows as separate frames (judder), so no bounce and shorter.
// Use: NumberAnimation with duration Motion.duration, easing.type Motion.type, easing.bezierCurve Motion.curve.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  readonly property bool off: Theme.game || Prefs.motion === "off"
  property real hz: 0   // highest refresh rate among the outputs (set by services/NiriConf.qml); 0 = not known yet
  readonly property bool smooth: hz >= 90
  readonly property bool calm: !smooth   // no overshoot
  readonly property real slowmo: Math.max(1, Number(Prefs.get("motion_slowmo", 1)) || 1)   // test knob (settings.toml motion_slowmo = 4): every animation x4 slower, to look at it
  readonly property real speed: (smooth ? 1 : 0.75) * slowmo
  readonly property real bounce: 1.1
  readonly property int duration: off ? 0 : Math.round(150 * speed)
  readonly property int type: Easing.BezierSpline
  readonly property var curve: [0.16, 1, 0.3, 1, 1, 1]
  // drops (launcher, popups). Nothing: crisp and mechanical - a fast decelerate, NO overshoot (was a macOS-like spring, 360 / 190 ms)
  readonly property var dropCurve: [0.2, 0, 0, 1, 1, 1]
  readonly property int dropOpen: off ? 0 : Math.round(280 * speed)
  readonly property int dropClose: off ? 0 : Math.round(160 * speed)
  // something growing out of a control in place (drop-down list): a soft start so the growth itself is seen, gentle landing
  readonly property var unfoldCurve: [0.35, 0, 0.1, 1, 1, 1]
  readonly property int unfold: off ? 0 : Math.round(380 * speed)
  // ---- The motion rule (60 Hz first; from Material 3 motion, Emil Kowalski, Apple WWDC23 springs, measured on the L490) ----
  // 1. Only opacity and position/size in WHOLE px move per frame; heavy content (blur, text pages) sits in a layer and is only composited.
  // 2. Every duration is a whole number of frames (fit): the last frame lands exactly on the target, no half-frame tail.
  // 3. Enter = decelerate (fast start, long settle), longer. Exit/fold = shorter (~60-70 %), never the same curve mirrored.
  // 4. Sizes: fast 100-150 ms (hover, press), normal 200-300 ms (panel, page), slow 320-400 ms (screen-sized: lock, launcher). Nothing > 500 ms.
  // 5. A new motion may start only after the window drew its first frames (heavy first frame never eats the motion), and a reversal continues from the current value.
  readonly property real frame: 1000 / (hz > 0 ? hz : 60)
  function fit(ms) { return off ? 0 : Math.round(Math.max(1, Math.round(ms / frame)) * frame) }
  readonly property int fast: fit(130 * slowmo)
  readonly property int normal: fit(250 * slowmo)
  readonly property int slow: fit(340 * slowmo)
  readonly property var enterCurve: [0.05, 0.7, 0.1, 1, 1, 1]    // decelerate: something appears / grows
  readonly property var exitCurve: [0.3, 0, 0.8, 0.15, 1, 1]     // accelerate: something leaves the screen
  readonly property var fadeCurve: [0.4, 0, 0.2, 1, 1, 1]       // opacity cross-fades: symmetric. The decelerate curve is for MOVEMENT only: on opacity it pops (70 % in the first 10 % of the time, measured)
  readonly property var emphasized: [0.2, 0, 0, 1, 1, 1]        // moves that begin and end on screen (the lock plate folding into the bar)
  readonly property real exitRatio: 0.65
}
