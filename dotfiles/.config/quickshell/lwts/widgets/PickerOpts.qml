// Options of the palette / wallpaper picker (Dark and light apart | Tint): drawn in the bar while the picker is open, in the picker itself
// where there is no bar. The state and the keys live in launcher/Picker.qml (`picker`).
import QtQuick
import qs.core
import qs.services

Row {   // options bar (one slim line, centred): palette = Dark and light apart (On / Off), wallpaper = Tint (Off / Soft / Full)
  property var picker: null
  property bool compact: false     // in the bar: the chips are a bit lower than the bar, so they never touch its edges
  readonly property int hh: compact ? Math.max(16, Prefs.barHeight - 8) : 24
  readonly property var pk: picker
  visible: pk.kind !== ""
  spacing: 10
  Text { text: pk.kind === "palette" ? "Dark and light apart" : "Tint"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale)
         anchors.verticalCenter: parent.verticalCenter }
  UiToggle {   // palette: On / Off (the shared switch, same as in Settings)
    visible: pk.kind === "palette"
    height: hh
    on: Look.split; focusedChip: pk.onSwitch
    onClicked: { pk.onSwitch = false; Prefs.set("palette_split", !Look.split) }
  }
  Row {   // wallpaper: tint chips (the recolour of the wallpaper in the palette colours)
    visible: pk.kind === "wallpaper"
    spacing: 4
    Repeater {
      model: pk.tints
      Rectangle {
        id: chip
        required property int index
        required property var modelData
        readonly property bool on: Prefs.get("recolor", "off") === modelData[0]
        width: 44; height: hh; radius: Math.min(Theme.radiusInner, height / 2)
        color: on ? Theme.accent : chipHit.containsMouse ? Theme.fillHover : "transparent"   // Nothing: outlined chip, solid when on
        border.width: pk.onSwitch && pk.optIdx === index ? 2 : on ? 0 : 1; border.color: pk.onSwitch && pk.optIdx === index ? Theme.ring : Theme.edge
        Behavior on color { ColorAnimation { duration: Motion.duration } }
        Text { anchors.centerIn: parent; text: chip.modelData[1]; color: chip.on ? Theme.accentInk : Theme.dim; font.family: Theme.font
               font.pixelSize: Math.round(11 * Theme.scale) }
        MouseArea { id: chipHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { pk.onSwitch = false; Look.setRecolor(chip.modelData[0]) } }
      }
    }
  }
  Text { visible: pk.kind === "wallpaper"; text: "Dim"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); leftPadding: 8
         anchors.verticalCenter: parent.verticalCenter }
  Row {   // wallpaper: dim chips (the wallpaper is drawn darker)
    visible: pk.kind === "wallpaper"
    spacing: 4
    Repeater {
      model: pk.dims
      Rectangle {
        id: dchip
        required property int index
        required property var modelData
        readonly property bool on: Prefs.get("wall_dim", "off") === modelData[0]
        width: 44; height: hh; radius: Math.min(Theme.radiusInner, height / 2)
        color: on ? Theme.accent : dchipHit.containsMouse ? Theme.fillHover : "transparent"
        border.width: pk.onSwitch && pk.optIdx === index + 3 ? 2 : on ? 0 : 1; border.color: pk.onSwitch && pk.optIdx === index + 3 ? Theme.ring : Theme.edge
        Behavior on color { ColorAnimation { duration: Motion.duration } }
        Text { anchors.centerIn: parent; text: dchip.modelData[1]; color: dchip.on ? Theme.accentInk : Theme.dim; font.family: Theme.font
               font.pixelSize: Math.round(11 * Theme.scale) }
        MouseArea { id: dchipHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { pk.onSwitch = false; Look.setDim(dchip.modelData[0]) } }
      }
    }
  }
}
