// Quick-settings tile (settings_spec 2.2): compact = square icon button; wide = icon + name (+ live status, dimmed, same line: every tile is one height).
// filled, no outline; on = a solid accent plate (Nothing), contents in accentInk; status in mono caps; focused = ring. Click = act, right click = details.
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.core

MouseArea {
  id: t
  property string icon
  property string label
  property string status: ""
  property var icons: []         // live info as icons instead of text (tray): the face is only these icons, no label
  property int iconFocus: -1     // keyboard: the icon the highlight sits on (-1 = the tile itself)
  property int iconOffset: 0     // first app icon shown (overflow slides this window)
  property var actions: []       // [{icon, label}]: when set the face is the picked app + these buttons (tray: Open / Quit)
  property string actionIcon: ""
  property int actionFocus: -1
  signal iconClicked(int index)  // real index in `icons`; -1 = the "+N" chip (next page)
  signal actionClicked(int index)
  property bool wide: true
  property bool on: false
  property real progress: -1     // 0..1 = a ring around the icon
  property string hero: ""        // a short number (dot-matrix) on the right of a wide tile, when there is room
  property bool alert: false      // red status line + red dot (no red fill)
  property bool info: false       // live data, no on/off: always bright (never the dim "off" look)
  readonly property bool lit: on || info
  readonly property bool timed: progress >= 0
  property bool focused: false
  property string hint: ""        // Alt held: the letter that triggers this tile (Alt+letter)
  signal act()
  signal details()
  implicitHeight: Math.round(38 * Theme.scale)   // launcher v2: compact, quiet tiles
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: m => m.button === Qt.RightButton ? details() : act()

  Rectangle {   // Nothing: compact tiles are circles (quick-settings buttons), wide tiles 6 px plates
    anchors.centerIn: parent
    width: parent.width; height: parent.height
    radius: Theme.radiusCtl
    // Nothing: every tile is an outline; "on" = a brighter outline + the red dot in the corner (not a filled Material plate)
    // launcher v2 (quiet): no outline; a faint tint plate, state = icon/text brightness + one white dot; red is for alerts only
    color: t.containsMouse ? Theme.fillHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)   // neutral, never the accent
    border.width: t.focused ? 2 : 0
    border.color: Theme.ring
    Rectangle { visible: t.on || t.alert; anchors { top: parent.top; right: parent.right; margins: 6 } width: 4; height: 4; radius: 2; color: t.alert ? Theme.red : Theme.text }
    Behavior on color { ColorAnimation { duration: Motion.duration } }
  }

  Item {   // compact + a running timer: the icon inside a draining ring (no numbers: they never fit a square)
    visible: !t.wide && t.icons.length === 0 && t.timed
    anchors.centerIn: parent; width: 26; height: 26
    ProgressRing { anchors.centerIn: parent; d: 26; p: Math.max(0, t.progress) }
    Icon { anchors.centerIn: parent; name: t.icon; fill: true; color: t.alert ? Theme.red : Theme.text; font.pixelSize: 13 }
  }
  // compact with a short live number (weather 8°, speed ↓84, battery 78%): the number IS the face, an icon alone says nothing
  readonly property string heroShort: t.hero.replace(/°C$/, "°")
  readonly property bool heroFace: !t.wide && t.icons.length === 0 && !t.timed && heroShort !== "" && heroShort.length <= 5
  Row {   // the tile's (live) icon + the number side by side, both full size (weather: sky + degrees)
    visible: t.heroFace
    anchors.centerIn: parent
    spacing: 3
    Icon { anchors.verticalCenter: parent.verticalCenter; name: t.icon; fill: true; color: t.alert ? Theme.red : t.lit ? Theme.text : Theme.dim; font.pixelSize: 16 }
    Text { anchors.verticalCenter: parent.verticalCenter; text: t.heroShort; color: t.alert ? Theme.red : t.lit ? Theme.text : Theme.dim
           font.family: Theme.dot; font.pixelSize: Math.round((t.heroShort.length > 3 ? 12 : 15) * Theme.scale) }
  }
  Icon {   // compact: icon only, centred
    visible: !t.wide && t.icons.length === 0 && !t.timed && !t.heroFace
    anchors.centerIn: parent
    name: t.icon; fill: t.on; color: t.alert ? Theme.red : t.lit ? Theme.text : Theme.dim
  }

  // picked-app face, by the width the tile really has: 0 = icons + text buttons, 1 = icon-only buttons, 2 = also no tray icon on the left,
  // 3 = also no app icon (just the two buttons)
  TextMetrics { id: tmOpen; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale); text: t.actions.length ? t.actions[0].label : "" }
  TextMetrics { id: tmQuit; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale); text: t.actions.length > 1 ? t.actions[1].label : "" }
  readonly property int needFull: 7 + 20 + 6 + 15 + 4 + (12 + 16 + 4 + tmOpen.advanceWidth) + 4 + (12 + 16 + 4 + tmQuit.advanceWidth) + 6
  readonly property int needIcons: 7 + 20 + 6 + 15 + 4 + 2 * 30 + 4 + 6
  readonly property int actMode: width >= needFull ? 0 : width >= needIcons ? 1 : width >= needIcons - 27 ? 2 : 3
  readonly property int cap: Math.max(1, Math.floor((width - 8 - 24) / 24))   // app icons that fit after the leading icon
  readonly property bool overflow: icons.length > cap
  readonly property int shown: overflow ? Math.max(1, cap - 1) : icons.length   // overflow: the last slot is the "+N" chip (pages through the rest)
  Icon {   // icons face (tray): the tile's own icon stays on the left, no text
    visible: t.icons.length > 0 && (t.actions.length === 0 || t.actMode < 2)
    name: t.icon; color: Theme.dim
    anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
  }
  Row {   // picked app: its icon, then the buttons on the tile (the tile never changes size)
    opacity: t.actions.length > 0 ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
    transform: Translate { x: t.actions.length > 0 ? 0 : 14; Behavior on x { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } } }   // the buttons slide in from the right
    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
    spacing: 4
    AppIcon { visible: t.actMode < 3; source: t.actionIcon; size: 15; anchors.verticalCenter: parent.verticalCenter }
    Repeater {
      model: t.actions
      MouseArea {
        required property var modelData
        required property int index
        implicitWidth: act.implicitWidth + 12; implicitHeight: 22
        Accessible.name: modelData.label
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: t.actionClicked(index)
        scale: pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
        Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: parent.containsMouse ? Theme.fillHover : Theme.tint
                    Behavior on color { ColorAnimation { duration: Motion.duration } } }
        Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"; border.width: 2; border.color: Theme.ring
                    opacity: t.actionFocus === parent.index ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } } }
        Row { id: act; anchors.centerIn: parent; spacing: 4
          Icon { name: parent.parent.modelData.icon; color: parent.parent.modelData.icon === "power" ? Theme.red : Theme.text; anchors.verticalCenter: parent.verticalCenter }
          Text { visible: t.actMode === 0; text: parent.parent.modelData.label; color: Theme.text; anchors.verticalCenter: parent.verticalCenter
                 font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) } }
      }
    }
  }
  Row {   // the apps' icons sit on the right; click one = pick it
    opacity: t.actions.length === 0 ? 1 : 0
    visible: t.icons.length > 0 && opacity > 0
    Behavior on opacity { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
    transform: Translate { x: t.actions.length === 0 ? 0 : -14; Behavior on x { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } } }   // the icons slide away to the left
    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
    spacing: 4
    Repeater {
      model: t.icons.slice(t.iconOffset, t.iconOffset + t.shown)
      MouseArea {
        required property var modelData
        required property int index
        implicitWidth: 20; implicitHeight: 20
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: t.iconClicked(t.iconOffset + index)
        scale: pressed ? 0.88 : t.iconFocus === t.iconOffset + index ? 1.12 : 1   // the picked icon lifts a little
        Behavior on scale { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
        Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: parent.containsMouse ? Theme.fillHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.duration } } }
        Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"; border.width: 2; border.color: Theme.ring
                    opacity: t.iconFocus === t.iconOffset + parent.index ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } } }
        AppIcon { anchors.centerIn: parent; source: parent.modelData; size: 15 }   // same engine as the bar
      }
    }
    MouseArea {   // overflow: "+N" = the full list
      visible: t.overflow
      implicitWidth: chip.implicitWidth + 10; implicitHeight: 20
      anchors.verticalCenter: parent.verticalCenter
      hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onClicked: t.iconClicked(-1)
      Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: parent.containsMouse ? Theme.fillHover : Theme.tint }
      Text { id: chip; anchors.centerIn: parent; text: t.iconOffset + t.shown < t.icons.length ? "+" + (t.icons.length - t.iconOffset - t.shown) : "‹"; color: Theme.text
             font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
    }
  }

  Item {   // wide: icon | caption + status | hero number (dot-matrix, only when it is short and the tile has room)
    visible: t.wide && t.icons.length === 0
    anchors { fill: parent; leftMargin: 5; rightMargin: 10 }
    readonly property bool showHero: t.hero !== "" && t.width >= 150
    Item {
      id: wIcon
      width: 28; height: 28; anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      Icon { anchors.centerIn: parent; name: t.icon; fill: t.on; color: t.alert ? Theme.red : t.lit ? Theme.text : Theme.dim }
      ProgressRing { visible: t.timed; anchors.centerIn: parent; d: 28; p: Math.max(0, t.progress) }
    }
    Text {
      id: wHero
      visible: parent.showHero
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: t.hero; color: t.alert ? Theme.red : t.lit ? Theme.text : Theme.dim
      font.family: Theme.dot; font.pixelSize: Math.round(17 * Theme.scale)
    }
    Column {   // Nothing: the caption (small, dim), the state under it
      anchors { left: wIcon.right; leftMargin: 7; right: parent.showHero ? wHero.left : parent.right; rightMargin: parent.showHero ? 8 : 0; verticalCenter: parent.verticalCenter }
      spacing: 1
      Text {
        width: parent.width; elide: Text.ElideRight
        text: t.label; color: Theme.dim
        font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(9 * Theme.scale)
      }
      Text {
        visible: text !== ""
        width: parent.width; elide: Text.ElideRight
        text: t.status
        color: t.alert ? Theme.red : t.lit ? Theme.text : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.7)
        font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(11 * Theme.scale)
      }
    }
  }

  Rectangle {   // Alt hint badge (launcher v2)
    visible: t.hint !== ""
    anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
    width: 14; height: 14; radius: 3
    color: Theme.text
    Text { anchors.centerIn: parent; text: t.hint; color: Theme.surface; font.family: Theme.label; font.pixelSize: 9; font.weight: Font.Bold }
  }
}
