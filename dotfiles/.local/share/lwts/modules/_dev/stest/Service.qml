import QtQuick
QtObject {
  property var use: Qt.createComponent("Use.qml")
  Component.onCompleted: { if (use.status === Component.Ready) use.createObject(this); else console.warn("STEST fail: " + use.errorString()) }
}
