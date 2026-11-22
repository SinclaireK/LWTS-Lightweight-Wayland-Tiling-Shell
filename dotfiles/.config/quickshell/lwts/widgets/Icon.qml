// Icon by its Phosphor name: Icon { name: "speaker-high" }. fill = solid variant (active state).
// Nothing look: drawn from Material Symbols Outlined (the icon set of the Nothing brand reference, Apache 2.0,
// ~/.local/share/fonts/material) through material.js (Phosphor name -> codepoint); a name with no mapping falls back to Phosphor.
import QtQuick
import qs.core
import "phosphor.js" as Ph
import "material.js" as Ms

Text {
  property string name
  property bool fill: false
  readonly property bool ms: Ms.map[name] !== undefined && Theme.iconsMs !== ""
  text: ms ? String.fromCodePoint(Ms.map[name]) : Ph.map[name] ? String.fromCodePoint(Ph.map[name]) : ""   // codepoints, no ligatures
  font.family: ms ? Theme.iconsMs : fill ? Theme.iconsFill : Theme.iconWeight === "bold" ? Theme.iconsBold : Theme.icons
  font.variableAxes: ms ? ({ "FILL": fill ? 1 : 0, "wght": 400, "GRAD": 0, "opsz": 20 }) : ({})
  font.pixelSize: Math.round(Theme.barPx * 1.15)
  color: Theme.text
  verticalAlignment: Text.AlignVCenter
}
