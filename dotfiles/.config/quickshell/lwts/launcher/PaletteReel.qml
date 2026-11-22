// Palette reel (case-opening style): cards slide under a fixed marker in the middle, the one under the marker is the choice
import QtQuick
import qs.core

Item {   // cards slide under a fixed marker in the middle; the one under the marker is the choice
  id: rl
  property var picker: null
  readonly property var pk: picker
  property int rowIdx: 0
  property var items: []
  property int selected: 0
  property real pos: 0
  readonly property bool cursor: pk.kind !== "" && pk.row === rowIdx && !pk.onSwitch
  readonly property real step: 216
  // The reel is endless: the cards run in a circle (a card's place is its index minus `pos`, wrapped), so the last card is next to the first.
  // `tgt` is where the animation is going; it only grows, so a fast scroll never turns back, `selected` (index) is kept by the picker.
  property real tgt: 0
  function run(ms) { anim.stop(); anim.from = pos; anim.to = tgt; anim.duration = ms; anim.start() }
  function shift(d, ms) { tgt += d; run(ms) }                      // d cards forward / back
  function jump(i, ms) {                                            // to card i by the short way round
    const n = items.length; if (n < 1) return;
    let delta = i - tgt; delta -= n * Math.round(delta / n); tgt += delta; run(ms)
  }
  function spin(i) {   // opening: the reel runs a few laps like a slot drum and slows down onto the card
    const n = items.length; if (n < 1) return;
    const travel = 21;   // casino: twenty-one cards (blackjack) and a bit over a second: an eye-catching run-in that does not make you wait
    anim.stop(); pos = i - travel; tgt = i; anim.from = pos; anim.to = i; anim.duration = 1300; anim.start()
  }
  clip: true
  focus: rowIdx === 0
  Keys.onPressed: e => { if (pk.handleKey(e)) e.accepted = true }   // the reel owns the keys (the input row is collapsed)
  NumberAnimation { id: anim; target: rl; property: "pos"; easing.type: Easing.OutQuart }
  WheelHandler {
    property real acc: 0
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: e => { acc += e.angleDelta.y || e.angleDelta.x; if (Math.abs(acc) < 120) return;
                    pk.onSwitch = false; pk.row = rl.rowIdx; pk.move(acc > 0 ? -1 : 1); acc = 0 }
  }
  Repeater {
    model: rl.items
    Item {
      id: slot
      required property int index
      required property var modelData
      readonly property real d: { const n = rl.items.length, v = index - rl.pos; return n > 0 ? v - n * Math.round(v / n) : v }
      readonly property real ad: Math.abs(d)
      width: 200; height: 112
      x: rl.width / 2 - width / 2 + d * rl.step
      y: 6
      visible: ad < rl.width / rl.step / 2 + 1
      scale: 1 - Math.min(ad, 1) * 0.1
      opacity: 1 - Math.min(ad, 3.5) * 0.15
      readonly property bool isWall: typeof modelData === "string"
      PaletteCard { visible: !slot.isWall; anchors.fill: parent; item: slot.isWall ? null : slot.modelData; current: rl.cursor && rl.selected === slot.index }
      Rectangle {   // wallpaper: a thumbnail, loaded only while the card is in view
        visible: slot.isWall; anchors.fill: parent; radius: Theme.radius; color: Theme.surface
        Image {
          anchors { fill: parent; margins: 1 }
          source: slot.isWall && slot.visible ? "file://" + slot.modelData : ""
          sourceSize: Qt.size(200, 112); asynchronous: true; cache: true; fillMode: Image.PreserveAspectCrop
        }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"
                    border.width: rl.cursor && rl.selected === slot.index ? 2 : 1; border.color: rl.cursor && rl.selected === slot.index ? Theme.accent : Theme.line }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pk.cardClicked(rl.rowIdx, slot.index) }
    }
  }
  Rectangle { x: parent.width / 2 - 1; y: 0; width: 2; height: 5; radius: 1; color: Theme.accent; opacity: rl.cursor ? 1 : 0.35 }   // the marker
  Rectangle { x: parent.width / 2 - 1; y: parent.height - 5; width: 2; height: 5; radius: 1; color: Theme.accent; opacity: rl.cursor ? 1 : 0.35 }
}
