// Nothing headline: the UI font ultra-thin, large. Page and window titles.
import QtQuick
import qs.core

Text {
  color: Theme.text
  font.family: Theme.font; font.weight: Font.Thin   // Nothing: editorial headings are ultra-thin; dot-matrix is kept for numerals only
  property int size: Math.round(24 * Theme.scale)   // set this, not font.pixelSize (the tracking follows it without a binding loop)
  font.pixelSize: size
  font.letterSpacing: -0.02 * size   // brand: headline tracking -20, sentence case (never caps)
}
