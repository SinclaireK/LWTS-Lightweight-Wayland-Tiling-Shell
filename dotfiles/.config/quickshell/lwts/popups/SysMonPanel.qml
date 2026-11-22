// SysMon (bar: click on the window title): CPU / RAM / GPU load, temperatures, the focused window's process
// with End process (hold to confirm, like power actions).
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: p
  spacing: 8
  Component.onCompleted: SysMon.active = true
  Component.onDestruction: SysMon.active = false

  component Meter: RowLayout {
    property string label
    property real value
    property string extra: ""
    Layout.fillWidth: true; spacing: 8
    Text { text: parent.label; color: Theme.text; Layout.preferredWidth: 40; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }   // Nothing: mono
    Item {   // Nothing style: dots instead of the bar; the dot size fits the free width exactly
      Layout.fillWidth: true; implicitHeight: 6
      DotMeter {
        anchors.verticalCenter: parent.verticalCenter
        count: 30; spacing: 2
        dotSize: Math.max(2, (parent.width - spacing * (count - 1)) / count)
        value: parent.parent.value
        hot: 0.85; hotColor: Theme.red
      }
    }
    Text { text: Math.round(parent.value * 100) + "%" + parent.extra; color: Theme.dim; Layout.preferredWidth: 96; horizontalAlignment: Text.AlignRight
           font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale) }
  }
  Meter { label: "CPU"; value: SysMon.cpu; extra: "  ·  " + SysMon.cpuTemp + "°" }
  Meter { label: "RAM"; value: SysMon.ram; extra: "  ·  " + SysMon.ramGb.toFixed(1) + " G" }
  Meter { label: "GPU"; value: SysMon.gpu; extra: "  ·  " + SysMon.gpuTemp + "°" }

  Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line; Layout.topMargin: 2 }
  RowLayout {
    Layout.fillWidth: true
    ColumnLayout {
      Layout.fillWidth: true; spacing: 0
      Text { Layout.fillWidth: true; elide: Text.ElideRight; text: SysMon.win.title || "No window"; color: Theme.text
             font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
      Text { text: SysMon.win.pid ? (SysMon.win.cls || "") + "  ·  PID " + SysMon.win.pid : ""; color: Theme.dim
             font.family: Theme.font; font.pixelSize: Math.round(10 * Theme.scale) }
    }
    MouseArea {   // End process: hold
      id: kill; hoverEnabled: true
      visible: !!SysMon.win.pid
      implicitWidth: kt.implicitWidth + 20; implicitHeight: 26
      cursorShape: Qt.PointingHandCursor
      property real hold: 0
      NumberAnimation on hold { id: ka; running: false; from: 0; to: 1; duration: 700; onFinished: if (kill.pressed) SysMon.kill() }
      onPressed: ka.restart()
      onReleased: { ka.stop(); hold = 0 }
      Rectangle { anchors.fill: parent; radius: Theme.radiusCtl; color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, kill.containsMouse ? 0.2 : 0.12); clip: true
                  Rectangle { width: parent.width * kill.hold; height: parent.height; color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.35) } }
      Text { id: kt; anchors.centerIn: parent; text: kill.hold > 0 ? "Keep holding…" : "End process"; color: Theme.red
             font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
    }
  }
}
