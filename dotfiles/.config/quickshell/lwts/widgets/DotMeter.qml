// Nothing-style level meter: a row of round dots instead of a bar. Each dot is on or off and blinks in 60 ms,
// so a moving level steps dot by dot like a dot-matrix display. Colours only from Theme: lit = text, over `hot` = hotColor (accent by default) (never hard-coded).
import QtQuick
import qs.core

Row {
  id: m
  property real value: 0        // 0..1
  property int count: 20
  property real fit: 0          // > 0: fill exactly this width (a slider track): dot count and spacing follow it
  property real gap: 3          // minimal gap in fit mode
  readonly property int n: fit > 0 ? Math.max(2, Math.floor((fit + gap) / (dotSize + gap))) : count
  property real dotSize: 4
  property real hot: 2          // level above which lit dots change colour; 2 = never
  property color hotColor: Theme.accent
  property color litColor: Theme.text
  property bool wave: false     // a change travels along the row (a few ms per dot) instead of every dot at once
  spacing: fit > 0 ? (fit - n * dotSize) / (n - 1) : 2
  Repeater {
    model: m.n
    Rectangle {
      required property int index
      readonly property real lit: m.value * m.n - index >= 0.5 ? 1 : 0   // Nothing: a dot is on or off (dot-matrix), never half-lit
      width: m.dotSize; height: m.dotSize; radius: width / 2
      color: lit > 0 && (index + 1) / m.n > m.hot ? m.hotColor : m.litColor
      opacity: 0.16 + 0.84 * lit   // unlit dots stay faintly visible (same idea as Theme.fill, but readable on any layer)
      Behavior on opacity { SequentialAnimation {   // a quick blink per dot; `wave` staggers the dots
        PauseAnimation { duration: m.wave && !Motion.off ? Math.min(index * 5, 140) : 0 }
        NumberAnimation { duration: Motion.off ? 0 : 60; easing.type: Easing.OutQuad } } }
    }
  }
}
