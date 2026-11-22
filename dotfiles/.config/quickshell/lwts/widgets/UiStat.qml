// Nothing bar status: either a mono-caps key and its value ("VOL 64", "BAT 81"; numbers in dot-matrix) or, with `icon` set,
// a thin Phosphor icon whose value (`value`) is shown beside it only while `showValue` is true. MouseArea: clicks / wheel are the owner's.
import QtQuick
import qs.core

MouseArea {
  id: st
  property string key
  property string icon                // set = icon mode (the key is not drawn)
  property color badge: "transparent"  // icon mode: a 4 px dot in the icon's corner, like the clock's unread dot; transparent = none
  property bool showValue: false      // icon mode: keep the value visible (battery); otherwise it unfolds on hover
  property string value
  property bool num: true            // value drawn in dot-matrix numerals
  property color tint: Theme.text
  property int px: Math.round(11 * Theme.scale)
  implicitWidth: (icon !== "" ? iconRow.implicitWidth : row.implicitWidth) + 14
  cursorShape: Qt.PointingHandCursor
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  hoverEnabled: true
  Row {   // icon mode
    id: iconRow
    visible: st.icon !== ""
    anchors.centerIn: parent
    Item {
      width: ic.implicitWidth; height: ic.implicitHeight; anchors.verticalCenter: parent.verticalCenter
      Icon { id: ic; anchors.centerIn: parent; name: st.icon; color: st.tint }
      Rectangle {   // the badge: only a state that needs a look (a problem, a connection, charging) lights it
        width: 4; height: 4; radius: 2; color: st.badge; opacity: st.badge.a > 0 ? 1 : 0
        anchors { top: parent.top; right: parent.right; topMargin: 1; rightMargin: -1 }
        Behavior on opacity { NumberAnimation { duration: Motion.duration } }
      }
    }
    Item {   // the value unfolds to the right of the icon: width eases, text clipped
      id: vbox
      readonly property bool open: st.showValue && st.value !== ""   // always-on values only (battery); no hover unfolding
      anchors.verticalCenter: parent.verticalCenter
      height: vt.implicitHeight; clip: true
      width: open ? vt.implicitWidth + 5 : 0
      Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
      Text { id: vt; x: 5; text: st.value; color: st.tint
             font.family: st.num ? Theme.dot : Theme.label; font.capitalization: Font.AllUppercase
             font.pixelSize: st.num ? st.px + 4 : st.px
             font.hintingPreference: Font.PreferNoHinting }
    }
  }
  Row {
    id: row
    visible: st.icon === ""
    anchors.centerIn: parent
    spacing: 5
    Text { anchors.verticalCenter: parent.verticalCenter; text: st.key; color: st.containsMouse ? Theme.text : Theme.dim
           font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: st.px }
    Text { anchors.verticalCenter: parent.verticalCenter; text: st.value; color: st.tint
           font.family: st.num ? Theme.dot : Theme.label; font.capitalization: Font.AllUppercase
           font.pixelSize: st.num ? st.px + 4 : st.px
           font.hintingPreference: Font.PreferNoHinting }
  }
}
