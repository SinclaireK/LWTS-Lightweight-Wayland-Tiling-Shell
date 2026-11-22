// Desktop widget card: the frame every widget of the desktop engine (services/Desk.qml) sits in. Glass plate with a 1 px outline,
// optional mono caps `caption`, content goes into the padded area (children land there). `inst` = placement ({id, w, h in cells..})
// set by DeskHost; `awake` = the engine's gate: bind every timer / process of the widget to it (false under a fullscreen window / lock).
import QtQuick
import qs.core
import qs.services

Item {
  id: card
  property var inst: null
  property string caption: ""
  readonly property bool awake: Desk.awake
  readonly property int pad: 12
  default property alias content: body.data
  readonly property alias body: body
  Rectangle {
    anchors.fill: parent; radius: Theme.radiusCard
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Prefs.opacityL1)
    border.color: Theme.edge; border.width: 1
  }
  UiCaption { visible: card.caption !== ""; x: card.pad; y: card.pad - 2; text: card.caption }
  Item { id: body; anchors.fill: parent; anchors.margins: card.pad }
}
