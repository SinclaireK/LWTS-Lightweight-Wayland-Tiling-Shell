// App icon engine: every app icon (tray, notifications, window switcher, list rows, tiles) as a clean monochrome glyph in one ink that follows the theme (light ink on a dark bar,
// dark ink on a light one) and keeps the icon's inner detail. Shader: widgets/appicon.frag (compiled appicon.frag.qsb).
// One ink only, no colour at all: `tray` (a tray item) whose status is NeedsAttention lights a 5 px dot of the same ink in the corner. Setting "tray_tint" (Settings > Bars > App icons) = orig turns the engine off (the original colours).
// Use: AppIcon { source: modelData.icon; tray: modelData; size: 16 }. Symbolic icons skip the detail pass (already one colour).
import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core

Item {
  id: ai
  property string source
  property var tray                    // optional SystemTrayItem
  property real size: Math.round(Theme.barPx * 1.1)   // as big as the glyph icons
  property real faint: 0.16            // opacity of a dot of the field on the transparent part
  property bool tint: Prefs.get("tray_tint", true)
  property color ink: Theme.text       // the dots' colour (default the theme's text)
  readonly property bool symbolic: /symbolic/i.test(String(source))
  readonly property bool attention: tray ? tray.status === Status.NeedsAttention : false
  implicitWidth: size; implicitHeight: size
  IconImage {
    anchors.fill: parent; source: ai.source; implicitSize: ai.size
    layer.enabled: ai.tint
    layer.effect: ShaderEffect {
      property color ink: ai.ink
      property real dark: (Theme.text.r * 0.299 + Theme.text.g * 0.587 + Theme.text.b * 0.114) > 0.5 ? 1 : 0   // light ink = dark bar
      property real detail: ai.symbolic ? 0 : 1
      property real cells: Math.max(8, ai.size)   // pixel grid of the dotted field + texel step of the contrast pass
      property real faint: ai.faint
      fragmentShader: "appicon.frag.qsb"
    }
  }
  Rectangle {   // the unread / attention dot, same language as the bar badges
    width: 5; height: 5; radius: 3; color: ai.ink
    opacity: ai.attention ? 1 : 0
    anchors { top: parent.top; right: parent.right; topMargin: -1; rightMargin: -2 }
    Behavior on opacity { NumberAnimation { duration: Motion.duration } }
  }
}
