// A dot-matrix glyph (widgets/dotglyphs.js, 7x7 chunky silhouette of big, almost touching dots as in the Nothing icons): `name`, `dot` / `gap` px.
// Only lit dots are drawn (no field of unlit dots); `ink` at `level`.
// `progress` 0..1 sweeps the lit dots red column by column (a held press). Dots switch on / off, never half-lit.
import QtQuick
import qs.core
import "dotglyphs.js" as Glyphs

Item {
  id: g
  property string name
  property int dot: 4
  property int gap: 1
  property color ink: Theme.text
  property real level: 1          // opacity of a lit dot
  property real progress: 0       // held-press sweep, left to right
  readonly property var bits: Glyphs.map[name] || []
  readonly property int n: bits.length
  implicitWidth: n * dot + (n - 1) * gap; implicitHeight: implicitWidth
  Grid {
    columns: Math.max(1, g.n); spacing: g.gap
    Repeater {
      model: g.n * g.n
      Rectangle {
        required property int index
        readonly property int cx: index % g.n
        readonly property bool lit: g.n > 0 && g.bits[Math.floor(index / g.n)][cx] === "#"
        readonly property bool swept: lit && g.progress > 0 && (cx + 0.5) / g.n <= g.progress
        width: g.dot; height: g.dot; radius: g.dot / 2
        color: swept ? Theme.red : g.ink
        opacity: lit ? (swept ? 1 : g.level) : 0   // not `visible`: a Grid skips invisible items and collapses
      }
    }
  }
}
