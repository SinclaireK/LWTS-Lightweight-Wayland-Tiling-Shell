// One theme as a tiny window: code lines in its own colours, accent button, the six terminal colours (palette picker card half)
import QtQuick
import qs.core

Rectangle {   // one theme as a tiny window: code lines in its own colours, accent button, the six terminal colours
  id: hf
  property var pal: null
  property string inner: ""    // "left" | "right": the side that touches the other half (square corners)
  readonly property var c: pal && pal.colors && pal.colors.length ? pal.colors : [Theme.surface, Theme.text, Theme.accent]
  readonly property var an: pal && pal.ansi && pal.ansi.length ? pal.ansi : [c[2], c[2], c[2], c[2], c[2], c[2]]
  readonly property var lines: [[[3, 0.42], [-1, 0.34]], [[1, 0.28], [2, 0.34], [-1, 0.16]], [[4, 0.34], [5, 0.30]]]   // [ansi index or -1 = text, share of the width]
  radius: Theme.radius
  color: c[0]
  Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: hf.radius; color: hf.color }
  Rectangle { visible: hf.inner === "left"; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: hf.radius; color: hf.color }
  Rectangle { visible: hf.inner === "right"; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: hf.radius; color: hf.color }
  Column {
    x: 10; y: 10; width: parent.width - 20; spacing: 5
    Repeater {
      model: hf.lines
      Row {
        required property var modelData
        spacing: 4
        Repeater {
          model: parent.modelData
          Rectangle {
            required property var modelData
            width: Math.max(4, (hf.width - 20) * modelData[1]); height: 5; radius: 2.5
            color: modelData[0] < 0 ? hf.c[1] : hf.an[modelData[0]]
            opacity: modelData[0] < 0 ? 0.55 : 1
          }
        }
      }
    }
  }
  Rectangle { x: 10; y: parent.height - 38; width: Math.min(44, parent.width - 20); height: 13; radius: Math.min(Theme.radiusInner, 6); color: hf.c[2] }
  Row {
    x: 10; y: parent.height - 18; spacing: 3
    Repeater { model: hf.an; Rectangle { required property string modelData; width: 8; height: 8; radius: 4; color: modelData } }
  }
}
