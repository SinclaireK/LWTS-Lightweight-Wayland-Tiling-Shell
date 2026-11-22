// Icon-only button: transparent at rest, a fill on hover, a fill + full-contrast icon when `on`. Nothing: 6 px rectangle.
// `icon`, `on`, `big` (40 px, filled glyph: the main action, e.g. play), `size` (30 px default).
import QtQuick
import qs.core

MouseArea {
  id: ib
  property string icon
  property bool on: false
  property bool big: false
  property int size: big ? 40 : 30
  implicitWidth: size; implicitHeight: size
  cursorShape: Qt.PointingHandCursor; hoverEnabled: true
  opacity: enabled ? 1 : 0.35
  Rectangle { anchors.fill: parent; radius: Theme.radiusCtl
              color: ib.big ? (ib.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.86) : Theme.accent)
                   : ib.on ? Theme.fillHover : ib.containsMouse ? Theme.fill : "transparent"
              Behavior on color { ColorAnimation { duration: Motion.duration } } }
  Icon { anchors.centerIn: parent; name: ib.icon; fill: ib.big || ib.on
         color: ib.big ? Theme.accentInk : ib.on ? Theme.text : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.8)
         font.pixelSize: Math.round(Theme.barPx * (ib.big ? 1.6 : 1.2)) }
}
