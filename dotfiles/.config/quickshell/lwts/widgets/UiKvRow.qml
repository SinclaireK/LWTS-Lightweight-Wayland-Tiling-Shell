// Quiet key/value row (launcher v2, panel-style rows): dim mono-caps key in a fixed column, then ONE of: value text, a dot track
// (`track` 0..1 + `trail` number on the right), or custom children (default property `extra`, e.g. tray icons). `led` = a live
// LED dot on the right. Click / Enter = act, right click = details, drag on the track = moved(v). `hint` = Alt letter badge.
import QtQuick
import QtQuick.Layouts
import qs.core

MouseArea {
  id: r
  property string key
  property string value: ""
  property real track: -1
  property string trail: ""
  property bool led: false
  property bool off: false            // muted / disabled: the dot track dims and the number reads MUTE
  property bool timed: false          // value shown as dot-matrix numerals (a running countdown)
  property bool focusedRow: false
  property string hint: ""
  property bool custom: false
  default property alias extra: holder.data
  signal act()
  signal details()
  signal moved(real v)
  property bool keyClickable: false   // the key itself is a button (sound row: switch the output)
  signal keyClicked()
  implicitHeight: Math.round(26 * Theme.scale)
  hoverEnabled: true
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: m => { if (r.track < 0) m.button === Qt.RightButton ? details() : act() }
  Rectangle {
    anchors.fill: parent; radius: Theme.radiusCtl
    color: r.containsMouse ? Theme.fillHover : "transparent"
    border.width: r.focusedRow ? 2 : 0; border.color: Theme.ring
    Behavior on color { ColorAnimation { duration: Motion.duration } }
  }
  RowLayout {
    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
    spacing: 10
    Text {
      visible: r.key !== ""   // no key = the content starts at the left edge
      Layout.preferredWidth: Math.round(60 * Theme.scale)
      text: r.key; color: keyMa.containsMouse ? Theme.accent : r.focusedRow ? Theme.text : Theme.dim; elide: Text.ElideRight
      font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale)
      MouseArea { id: keyMa; anchors.fill: parent; enabled: r.keyClickable; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r.keyClicked() }
    }
    Slider { visible: r.track >= 0; opacity: r.off ? 0.3 : 1; Layout.fillWidth: true; dotSize: 4; gap: 4; value: Math.max(0, r.track); onMoved: v => r.moved(v) }
    Text {
      visible: r.track >= 0
      text: r.off ? "MUTE" : r.trail; color: r.off ? Theme.red : Theme.text; Layout.preferredWidth: Math.max(30, implicitWidth); horizontalAlignment: Text.AlignRight
      font.family: Theme.dot; font.pixelSize: Math.round(13 * Theme.scale)
    }
    Text {
      visible: r.track < 0 && !r.custom
      Layout.fillWidth: true; elide: Text.ElideRight
      text: r.value; color: Theme.text
      font.family: r.timed ? Theme.dot : Theme.label; font.capitalization: r.timed ? Font.MixedCase : Font.AllUppercase
      font.pixelSize: Math.round((r.timed ? 14 : 10) * Theme.scale)
    }
    Item { id: holder; visible: r.custom; Layout.fillWidth: true; Layout.preferredHeight: 20; clip: true }
    Rectangle { visible: r.led && r.hint === ""; width: 4; height: 4; radius: 2; color: Theme.accent }
    Rectangle {
      visible: r.hint !== ""; width: 14; height: 14; radius: 3; color: Theme.accent
      Text { anchors.centerIn: parent; text: r.hint; color: Theme.surface; font.family: Theme.label; font.pixelSize: 9; font.weight: Font.Bold }
    }
  }
}
