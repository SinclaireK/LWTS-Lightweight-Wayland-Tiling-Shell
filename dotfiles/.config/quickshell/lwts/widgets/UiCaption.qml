// Nothing style caption: small mono capitals with wide tracking (group headers, section titles). One definition for all of them.
import QtQuick
import qs.core

Text {
  color: Theme.dim
  font.family: Theme.label; font.capitalization: Font.AllUppercase; font.letterSpacing: 0   // brand: mono tracking 0
  font.weight: Font.Normal; font.pixelSize: Math.round(10 * Theme.scale)
}
