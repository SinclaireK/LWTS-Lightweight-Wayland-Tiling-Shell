// One trigger for GamepadView: dots lit up to the hand, Start / Full press marks. `view` = the GamepadView.
import QtQuick
import qs.core
import qs.services
import qs.widgets

Item {
  property var view: null           // the GamepadView: inline components cannot see the file's ids
  id: tcol
  property int which: 0
  property real h: 120
  readonly property string side: which ? "r" : "l"
  readonly property real inV: view.trig[which]
  readonly property int n: Math.max(8, Math.round(h / 10))
  width: 26; height: h
  Repeater {
    model: tcol.n
    Rectangle {
      required property int index
      readonly property real at: index / (tcol.n - 1)
      width: 7; height: 7; radius: 3.5; x: 9; y: tcol.h - 7 - at * (tcol.h - 7)
      color: Theme.text; opacity: at <= tcol.inV ? 1 : 0.16
    }
  }
  Repeater {
    model: ["ts", "te"]
    Rectangle {
      required property string modelData
      width: 26; height: 2; color: Theme.accent; y: tcol.h - 4 - view.t[tcol.side + modelData] / 100 * (tcol.h - 7)
    }
  }
}
