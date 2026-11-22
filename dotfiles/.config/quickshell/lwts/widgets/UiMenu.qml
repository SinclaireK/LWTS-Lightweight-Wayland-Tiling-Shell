// Context menu (Nothing look): glass plates with 1 px outline, mono caps rows, hairline separators, LED dot = on / current, caret = submenu.
// Fills its parent (the surface it lives on): a click outside, Esc or a finished action emits done(). Keys: up / down, right (open submenu),
// left (back, at the root = close), Enter, Esc. Items (array of plain objects):
// Thin by design (22 px rows, 10 px caps): rare actions go into a "More" submenu, the common ones into one icon strip (Win11 style):
//   { strip: [{ icon, off?, act?, keep?, ask? }, ...] }   // one row of icon buttons (Cut Copy Rename Trash)
//   { label, icon?, hint?, on? (true/false = LED), off? (dimmed, not clickable), info? (plain text row, not selectable), sub?: [items], act?: function, keep?: true (stay open), sep?: true,
//     ask?: { title, text?, accept: function(text) } }   // ask = the plate turns into a one-line text field, Enter accepts
// `ax` `ay` = where the menu opens (the cursor); submenus open to the right, or to the left when there is no room.
import QtQuick
import qs.core

FocusScope {
  id: m
  property var items: []
  property real ax: 0
  property real ay: 0
  property int cw: 184
  signal done()
  function close(why) { done() }   // why: only for reading the code

  property var sels: [-1]      // selected row per open level
  property int stripSel: 0     // selected button while the selected row is an icon strip
  property var asking: null    // the ask object while a text field is shown
  readonly property var levels: {   // item arrays of the open levels
    const out = [items];
    for (let k = 0; k < sels.length - 1; k++) { const it = out[k][sels[k]]; if (it && it.sub) out.push(it.sub); else break }
    return out;
  }
  readonly property int deep: levels.length - 1
  function sel() { return sels[deep] }
  function rowH(it) { return it.sep ? 7 : it.strip ? 30 : 22 }
  function plateH(arr) { let h = 8; for (const it of arr) h += rowH(it); return h }
  function rowY(arr, i) { let y = 4; for (let j = 0; j < i; j++) y += rowH(arr[j]); return y }
  function plateX(k) {   // levels go right, flip left when the screen edge is near
    let x = ax; const w = cw + 2;
    for (let i = 1; i <= k; i++) x = (x + w + cw > width && x - w >= 0) ? x - w : x + w;
    return Math.max(0, Math.min(x, width - cw));
  }
  function plateY(k) {
    let y = ay;
    for (let i = 1; i <= k; i++) y += rowY(levels[i - 1], sels[i - 1]) - 4;
    return Math.max(0, Math.min(y, height - plateH(levels[k])));
  }
  function setSel(k, i) {   // hover / keys: select row i on level k, cut deeper levels, open a submenu when the row has one
    const it = levels[k][i]; if (!it || it.sep || it.info) return;
    if (sels[k] !== i) stripSel = 0;
    const s = sels.slice(0, k + 1); s[k] = i;
    if (it.sub && !it.off) s.push(-1);
    sels = s;
  }
  function activateStrip(k, i, j) {
    const it = levels[k][i], b = it && it.strip ? it.strip[j] : null; if (!b || b.off) return;
    if (b.ask) { asking = b.ask; return }
    if (b.act) b.act();
    if (!b.keep) close("action");
  }
  function activate(k, i) {
    const it = levels[k][i]; if (!it || it.sep || it.off || it.info) return;
    if (it.sub) { const s = sels.slice(0, k + 1); s[k] = i; s.push(0); sels = s; return }
    if (it.ask) { asking = it.ask; return }
    if (it.act) it.act();
    if (!it.keep) close("action");
  }
  function step(d) {
    const arr = levels[deep]; let i = sel();
    for (let n = 0; n < arr.length; n++) { i = (i + d + arr.length) % arr.length; if (!arr[i].sep && !arr[i].off && !arr[i].info) break }
    if (i === sel() && (arr[i].off || arr[i].info)) return;
    setSel(deep, i);
  }
  Keys.onPressed: e => {
    if (asking) { if (e.key === Qt.Key_Escape) { asking = null; e.accepted = true } return }
    const cur = levels[deep][sel()], strip = cur && cur.strip ? cur.strip : null;
    if (strip && e.key === Qt.Key_Left && stripSel > 0) { stripSel--; e.accepted = true; return }
    if (strip && e.key === Qt.Key_Right && stripSel < strip.length - 1) { stripSel++; e.accepted = true; return }
    if (strip && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) { activateStrip(deep, sel(), stripSel); e.accepted = true; return }
    if (e.key === Qt.Key_Escape) close("esc");
    else if (e.key === Qt.Key_Down) step(1);
    else if (e.key === Qt.Key_Up) step(-1);
    else if (e.key === Qt.Key_Right) { const it = levels[deep][sel()]; if (it && it.sub) activate(deep, sel()) }
    else if (e.key === Qt.Key_Left) { if (deep > 0) sels = sels.slice(0, deep); else close("left-at-root") }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { if (sel() >= 0) activate(deep, sel()) }
    else return;
    e.accepted = true;
  }

  // The host puts the menu on its own full-output surface (Overlay, exclusive keyboard): a click anywhere else lands on the closer below,
  // so no focus bookkeeping is needed (closing on focus changes of a Bottom layer surface killed the menu under the click).
  Component.onCompleted: forceActiveFocus()

  MouseArea {   // outside: any click closes
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onPressed: m.close("click-out")
  }

  Repeater {
    model: m.levels.length
    Rectangle {
      id: plate
      required property int index
      readonly property var arr: m.levels[index]
      readonly property bool last: index === m.deep
      x: m.plateX(index); y: m.plateY(index)
      width: m.cw; height: askHere ? 70 : m.plateH(arr)
      readonly property bool askHere: !!m.asking && last
      radius: Theme.radiusCard
      color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Math.max(Prefs.opacityL0, 0.96))
      border.color: Theme.edge; border.width: 1
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks on a plate never reach the closer below

      Column {
        visible: !plate.askHere
        x: 4; y: 4; width: parent.width - 8
        Repeater {
          model: plate.arr
          Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool picked: m.sels[plate.index] === index
            width: parent.width; height: m.rowH(modelData)
            UiDotLine { visible: !!row.modelData.sep; anchors.verticalCenter: parent.verticalCenter; width: parent.width }
            Rectangle {
              visible: !row.modelData.sep && !row.modelData.strip && row.picked && !row.modelData.off
              anchors.fill: parent; radius: Theme.radiusInner; color: Theme.fillHover
            }
            Row {   // icon strip: equal buttons in one row
              visible: !!row.modelData.strip
              anchors.fill: parent
              Repeater {
                model: row.modelData.strip || []
                Item {
                  id: sb
                  required property var modelData
                  required property int index
                  width: row.width / (row.modelData.strip ? row.modelData.strip.length : 1); height: row.height
                  readonly property bool hot: row.picked && m.stripSel === index && !modelData.off
                  Rectangle { anchors.fill: parent; anchors.margins: 1; radius: Theme.radiusInner; color: sb.hot ? Theme.fillHover : "transparent" }
                  Icon { anchors.centerIn: parent; name: sb.modelData.icon || ""; font.pixelSize: 16; color: Theme.text; opacity: sb.modelData.off ? 0.35 : 1 }
                  MouseArea {
                    anchors.fill: parent; hoverEnabled: true; enabled: !sb.modelData.off
                    onEntered: { m.setSel(plate.index, row.index); m.stripSel = sb.index }
                    onClicked: m.activateStrip(plate.index, row.index, sb.index)
                  }
                }
              }
            }
            Item {
              visible: !row.modelData.sep && !row.modelData.strip
              anchors.fill: parent; opacity: row.modelData.off ? 0.4 : 1
              Rectangle {   // LED: lit = on, ring = off (only rows that carry a state)
                visible: row.modelData.on !== undefined
                x: 8; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3
                color: row.modelData.on ? Theme.accent : "transparent"
                border.color: row.modelData.on ? Theme.accent : Theme.edge; border.width: 1
              }
              Icon {
                visible: row.modelData.on === undefined && !!row.modelData.icon
                x: 5; anchors.verticalCenter: parent.verticalCenter
                name: row.modelData.icon || ""; font.pixelSize: 13; color: Theme.dim
              }
              Text {
                x: 24; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 24 - 26
                text: row.modelData.label || ""; elide: Text.ElideRight
                color: Theme.text; font.family: Theme.label; font.capitalization: Font.AllUppercase
                font.pixelSize: Math.round(10 * Theme.scale)
              }
              UiCaption {
                visible: !!row.modelData.hint && !row.modelData.sub
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.hint || ""
              }
              Icon {
                visible: !!row.modelData.sub
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                name: "caret-right"; font.pixelSize: 11; color: Theme.dim
              }
            }
            MouseArea {
              anchors.fill: parent; enabled: !row.modelData.sep && !row.modelData.info
              hoverEnabled: true
              onEntered: if (!row.modelData.off) m.setSel(plate.index, row.index)
              onClicked: m.activate(plate.index, row.index)
            }
          }
        }
      }

      Item {   // ask: one-line field
        visible: plate.askHere
        anchors.fill: parent; anchors.margins: 10
        UiCaption { id: askCap; text: m.asking ? m.asking.title : "" }
        Rectangle {
          anchors.top: askCap.bottom; anchors.topMargin: 6; width: parent.width; height: 24
          radius: Theme.radiusInner; color: "transparent"; border.color: Theme.edge; border.width: 1
          TextInput {
            id: field
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
            font.family: Theme.label; font.pixelSize: Math.round(10 * Theme.scale); clip: true
            text: m.asking ? (m.asking.text || "") : ""
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
            Keys.onReturnPressed: { const a = m.asking; if (a && text.trim() !== "") { a.accept(text.trim()); m.close("ask-accept") } }
            Keys.onEnterPressed: { const a = m.asking; if (a && text.trim() !== "") { a.accept(text.trim()); m.close("ask-accept") } }
            Keys.onEscapePressed: m.asking = null
          }
        }
        UiCaption { anchors.bottom: parent.bottom; text: "ENTER OK · ESC BACK" }
      }
    }
  }
}
