// Nothing: a dotted rule (1 px dots every 4 px) instead of a solid hairline - the dot-matrix motif in separators.
// One tiled SVG, cheap for long lists. Colour from Theme (default: the hairline colour).
import QtQuick
import qs.core

Image {
  property color color: Theme.dim
  property real strength: 0.55
  height: 1
  fillMode: Image.Tile
  horizontalAlignment: Image.AlignLeft
  smooth: false
  source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='4' height='1'><rect width='1' height='1' fill='%23"
          + color.toString().slice(-6) + "' fill-opacity='" + strength + "'/></svg>"
}
