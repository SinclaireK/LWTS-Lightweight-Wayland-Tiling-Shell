// Nothing style numerals: dot-matrix (Doto) bold with round dots. The one definition for every big number: bar clock, lock clock, OSD level.
// Set the size at the call site (font.pixelSize); Doto is unreadable under ~13 px. Missing Doto falls back to the UI font.
import QtQuick
import qs.core

Text {
  color: Theme.text
  font.family: Theme.dot   // static heavy round-dot face (core/Theme.qml)
  property int size: Math.round(14 * Theme.scale)   // integer pixel size
  font.pixelSize: size
  font.hintingPreference: Font.PreferNoHinting
}
