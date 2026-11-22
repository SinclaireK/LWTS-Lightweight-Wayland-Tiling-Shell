// Column header of a sortable list (Tasks): mono caps label, a red dot while it is the sort key, an optional total beside it.
import QtQuick
import qs.core

MouseArea {
  id: h
  property string label
  property string total: ""
  property bool active: false
  property bool alignRight: false
  implicitHeight: 20; cursorShape: Qt.PointingHandCursor
  Row {
    spacing: 6; anchors.verticalCenter: parent.verticalCenter
    anchors.right: h.alignRight ? parent.right : undefined; anchors.rightMargin: 6
    anchors.left: h.alignRight ? undefined : parent.left; anchors.leftMargin: 10
    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 2.5; color: Theme.red; opacity: h.active ? 1 : 0 }
    UiCaption { text: h.label; color: h.active ? Theme.text : Theme.dim }
    UiCaption { text: h.total; color: Theme.text }
  }
}
