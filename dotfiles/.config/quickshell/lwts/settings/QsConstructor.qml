// Settings -> Features -> Layout: the launcher's quick part, built from the SAME pieces it shows (UiChip text switches, UiKvRow
// rows, Tile tiles) on a plate like the launcher, + an inspector for the picked item + the bank of items that are off.
// The zone is the look: Text (only on/off switches may be text) or Tiles (icon / default / wide). Nothing here fires an item.
// Keys (forwarded by SettingsNew while this tab is open): arrows pick (preview, then the bank); Space = grab, then ← → move it,
// ↓ to tiles, ↑ to text, Space / Enter / Esc drop; W text / tile; S size; Delete off; Enter on a bank item = add.
// Mouse: click picks; the inspector rows switch look / size / place / remove; click a bank row = add.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

Item {
  id: root
  implicitHeight: mainCol.implicitHeight

  readonly property var all: Tiles.all
  function isRow(id) { const d = all[id]; return !!d && (!!d.toggleless || !!d.drill || !!d.progress) }
  readonly property var order: Tiles.flatten(Tiles.layoutRows).map(t => t.id).filter(id => !!all[id] && id !== "tray")   // the tray is a switch in Bars, not a layout item
  readonly property var widgets: order.filter(id => Tiles.wideIds.includes(id))
  readonly property var chips: order.filter(id => !isRow(id) && !widgets.includes(id))
  readonly property var rowsT: order.filter(id => isRow(id) && !widgets.includes(id))
  readonly property var bank: Tiles.bank.filter(id => id !== "tray")
  // the bank in three groups: switches (may be text) / tiles (live info, tools) / own data widgets (widgets.json)
  readonly property var bankGroups: [["Switches", bank.filter(id => !all[id].toggleless)],
                                     ["Tiles", bank.filter(id => all[id].toggleless && !id.startsWith("x_"))],
                                     ["Own", bank.filter(id => id.startsWith("x_"))]].filter(g => g[1].length)
  readonly property var bankFlat: [].concat(...bankGroups.map(g => g[1]))
  readonly property var zones: [chips, rowsT, widgets, bankFlat]
  readonly property var focusList: [].concat(chips, rowsT, widgets, bankFlat)
  readonly property var shortNames: ({ notif: "Notif", profile: "Profile", sysmon: "System", flight: "Flight", dnd: "DND", wifi: "Wi-Fi", clip: "Clip" })
  function nameOf(id) { return shortNames[id] || (all[id] ? all[id].label() : id) }

  property string sel: ""
  property bool grabbed: false
  readonly property string cur: focusList.includes(sel) ? sel : (focusList[0] || "")
  readonly property var curT: all[cur] || null
  readonly property bool curInBank: bankFlat.includes(cur)
  readonly property bool curWidget: widgets.includes(cur)
  readonly property bool canText: !!cur && !Tiles.tileOnly(cur) && !Tiles.textOnly(cur)
  function zoneOf(id) { for (let z = 0; z < zones.length; z++) if (zones[z].includes(id)) return z; return -1 }

  function moveTile(d) {   // a grabbed tile: one step through the rows (past a row's end = into the next row)
    const rows = Tiles.tileRowIds(widgets, prev.width, Math.round(38 * Theme.scale)).map(r => r.slice());
    let r = rows.findIndex(x => x.includes(cur)); if (r < 0) return;
    let i = rows[r].indexOf(cur); rows[r].splice(i, 1);
    if (d < 0) { if (i > 0) rows[r].splice(i - 1, 0, cur); else if (r > 0) rows[r - 1].push(cur); else rows[r].unshift(cur) }
    else { if (i < rows[r].length) rows[r].splice(i + 1, 0, cur); else if (r < rows.length - 1) rows[r + 1].unshift(cur); else rows.push([cur]) }
    Tiles.setTileRows(rows);
  }
  function moveInZone(d) {   // swap with the neighbour of the same zone, in the global order
    if (curWidget) { moveTile(d); return }
    const z = zones[zoneOf(cur)], i = z.indexOf(cur), j = i + d;
    if (curInBank || j < 0 || j >= z.length) return;
    const o = order.slice(), a = o.indexOf(cur), b = o.indexOf(z[j]);
    o[a] = z[j]; o[b] = cur;
    Tiles.setOrder(o);
  }
  function setLook(v) { if (!cur) return; const id = cur; Tiles.setLook(id, v); sel = id; if (v === "off") grabbed = false }
  function add(id) { sel = id; Tiles.setLook(id, Tiles.tileOnly(id) ? "widget" : "text") }
  function toggleLook() { if (!curInBank && canText) setLook(curWidget ? "text" : "widget") }
  function stepZone(d) {
    let z = zoneOf(cur) + d;
    while (z >= 0 && z < zones.length && zones[z].length === 0) z += d;
    if (z < 0 || z >= zones.length) return false;
    sel = zones[z][0]; return true;
  }
  function handleKey(e) {
    const k = e.key;
    if (!focusList.length) return false;
    if (grabbed) {
      if (k === Qt.Key_Left) moveInZone(-1);
      else if (k === Qt.Key_Right) moveInZone(1);
      else if (k === Qt.Key_Down && !curWidget) setLook("widget");
      else if (k === Qt.Key_Up && curWidget && canText) setLook("text");
      else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) grabbed = false;
      else if (k === Qt.Key_Delete || k === Qt.Key_Backspace) setLook("off");
      else if (k !== Qt.Key_Up && k !== Qt.Key_Down) return false;
      return true;
    }
    const i = focusList.indexOf(cur);
    if (k === Qt.Key_Left) { if (i <= 0) return false; sel = focusList[i - 1]; return true }
    if (k === Qt.Key_Right) { if (i >= focusList.length - 1) return false; sel = focusList[i + 1]; return true }
    if (k === Qt.Key_Up) return stepZone(-1);
    if (k === Qt.Key_Down) return stepZone(1);
    if (k === Qt.Key_Space && !curInBank) { grabbed = true; return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && curInBank) { add(cur); return true }
    if (k === Qt.Key_W) { toggleLook(); return true }
    if (k === Qt.Key_S && curWidget) { Tiles.cycleSize(cur); return true }
    if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && !curInBank) { setLook("off"); return true }
    return false;
  }
  function pick(id) { if (grabbed && id !== cur) grabbed = false; sel = id }

  component Grab: Rectangle {   // accent outline on the grabbed item
    property string who: ""
    anchors.fill: parent; radius: Theme.radiusInner; color: "transparent"
    visible: root.grabbed && root.cur === who
    border.width: 2; border.color: Theme.accent
  }

  ColumnLayout {
    id: mainCol
    width: parent.width
    spacing: 8
    RowLayout {   // inspector strip: the picked item + what can be done with it (each control shows its key)
      Layout.fillWidth: true; Layout.preferredHeight: Math.round(34 * Theme.scale); spacing: 8
      Icon { name: root.curT ? root.curT.icon : "square"; fill: !!root.curT && root.curT.on(); color: Theme.text; font.pixelSize: Math.round(20 * Theme.scale) }
      ColumnLayout {
        Layout.preferredWidth: Math.round(120 * Theme.scale); spacing: 0
        Text { text: root.cur ? root.nameOf(root.cur) : ""; color: Theme.text; font.family: Theme.label; font.capitalization: Font.AllUppercase
               font.pixelSize: Math.round(13 * Theme.scale); Layout.fillWidth: true; elide: Text.ElideRight }
        UiCaption { color: (root.grabbed || !!root.dragId) ? Theme.accent : Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); Layout.fillWidth: true; elide: Text.ElideRight
                    text: (root.grabbed || !!root.dragId) ? "Moving" : root.curInBank ? "Off" : root.curT && root.curT.status && root.curT.status() ? root.curT.status() : (root.curT && root.curT.on() ? "On" : "Off") }
      }
      UiSegmented { visible: !root.curInBank && root.canText; options: [["text", "Text"], ["widget", "Tile"]]; current: root.curWidget ? "widget" : "text"
                    onPicked: id => root.setLook(id) }
      UiKeyCap { k: "W"; visible: !root.curInBank && root.canText }
      UiSegmented { visible: !root.curInBank && root.curWidget; options: [["icon", "Icon"], ["default", "Name"]]; current: Tiles.sizeOf(root.cur)
                    onPicked: id => { if (Tiles.sizeOf(root.cur) !== id) Tiles.cycleSize(root.cur) } }
      UiKeyCap { k: "S"; visible: !root.curInBank && root.curWidget }
      Item { Layout.fillWidth: true }
      UiButton { visible: !root.curInBank; text: "‹"; flat: true; onClicked: root.moveInZone(-1) }
      UiButton { visible: !root.curInBank; text: "›"; flat: true; onClicked: root.moveInZone(1) }
      UiButton { visible: !root.curInBank; text: "Off"; flat: true; onClicked: root.setLook("off") }
      UiKeyCap { k: "Del"; visible: !root.curInBank }
      UiButton { visible: root.curInBank; text: Tiles.tileOnly(root.cur) ? "Add as tile" : "Add as text"; flat: true; onClicked: root.add(root.cur) }
      UiKeyCap { k: "Enter"; visible: root.curInBank }
    }
    UiDotLine { Layout.fillWidth: true }
    RowLayout {
    Layout.fillWidth: true
    spacing: 18

    Rectangle {   // the preview on a plate like the launcher drop
      id: plate
      Layout.preferredWidth: Math.round(400 * Theme.scale) + 24; Layout.alignment: Qt.AlignTop
      implicitHeight: prev.implicitHeight + 24
      radius: Theme.radiusCard; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL2)
      border.width: 1; border.color: Theme.line
      QsDragArea { host: root; anchors.fill: parent; from: prev; onTap: id => root.pick(id) }
      ColumnLayout {
        id: prev
        x: 12; y: 12; width: parent.width - 24
        spacing: 6
        UiCaption { color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); text: "Text  ·  switches" }
        Flow {
          id: chipFlow
          Layout.fillWidth: true
          visible: root.chips.length > 0
          Repeater {
            model: root.chips
            UiChip {
              required property string modelData
              readonly property string tid: modelData
              width: chipFlow.width / Math.max(1, Math.min(6, root.chips.length))
              text: root.nameOf(modelData); on: root.all[modelData].on()
              focusedChip: root.cur === modelData && !root.grabbed
              onAct: root.pick(modelData)
              Grab { who: modelData }
            }
          }
        }
        Repeater {
          model: root.rowsT
          UiKvRow {
            required property string modelData
            readonly property string tid: modelData
            Layout.fillWidth: true
            key: root.nameOf(modelData)
            value: root.all[modelData].status ? root.all[modelData].status() : ""
            focusedRow: root.cur === modelData && !root.grabbed
            onAct: root.pick(modelData)
            Grab { who: modelData }
          }
        }
        UiCaption { color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); visible: root.chips.length + root.rowsT.length === 0; text: "—" }
        UiDotLine { Layout.fillWidth: true }
        UiCaption { id: tilesCap; color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); text: "Tiles" }
        ColumnLayout {
          id: tilesCol
          Layout.fillWidth: true
          visible: root.widgets.length > 0
          spacing: 6
          Repeater {
            model: Tiles.tileRows(root.widgets, prev.width, Math.round(38 * Theme.scale), 6)
            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: modelData.spacing
              Repeater {
                model: parent.modelData.items
                Tile {
                  required property var modelData
                  readonly property string tid: modelData.id
                  readonly property var t: root.all[tid]
                  Layout.preferredWidth: modelData.w
                  wide: Tiles.sizeOf(tid) !== "icon"
                  readonly property var f: Tiles.face(tid)
            icon: f.icon; label: root.nameOf(tid); status: f.status; hero: f.hero; alert: f.alert; info: f.info; on: t.on()
                  progress: t.progress ? t.progress() : -1
                  focused: root.cur === tid && !root.grabbed
                  onAct: root.pick(tid)
                  Grab { who: tid }
                }
              }
            }
          }
        }
        UiCaption { color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); visible: root.widgets.length === 0; text: "—" }
      }
    }

    ColumnLayout {   // the bank
      id: side
      Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
      spacing: 6
      Item {   // the bank (also a drop target: drop a tile here = off)
      Layout.fillWidth: true; implicitHeight: bankCol.implicitHeight
      Rectangle { anchors.fill: parent; anchors.margins: -4; radius: Theme.radiusInner; color: "transparent"
                  border.width: root.dragId && root.dropZone === "off" ? 2 : 0; border.color: Theme.accent }
      ColumnLayout {
      id: bankCol
      width: parent.width; spacing: 6
      Repeater {   // the bank: what is off, in groups
        model: root.bankGroups
        ColumnLayout {
          id: grp
          required property var modelData
          Layout.fillWidth: true; spacing: 2
          UiCaption { color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); text: grp.modelData[0] }
          Flow {
            Layout.fillWidth: true; spacing: 2
            Repeater {
              model: grp.modelData[1]
              MouseArea {
                id: bi
                required property string modelData
                readonly property string tid: modelData
                readonly property bool focused: root.cur === modelData
                width: side.width; height: Math.round(22 * Theme.scale)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.add(modelData)
                Rectangle { anchors.fill: parent; radius: Theme.radiusInner; color: bi.containsMouse ? Theme.fillHover : "transparent"
                            border.width: bi.focused ? 2 : 0; border.color: Theme.ring }
                RowLayout {
                  anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                  spacing: 6
                  Icon { name: root.all[bi.modelData].icon; color: Theme.dim; font.pixelSize: Math.round(13 * Theme.scale) }
                  Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.nameOf(bi.modelData); color: bi.focused ? Theme.text : Theme.dim
                         font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
                  Text { text: "+"; color: Theme.dim; font.family: Theme.label; font.pixelSize: Math.round(12 * Theme.scale) }
                }
              }
            }
          }
        }
      }
      UiCaption { color: Theme.dim; font.pixelSize: Math.round(10 * Theme.scale); visible: root.bankFlat.length === 0; text: "Everything is on" }
      Item { Layout.fillWidth: true; Layout.preferredHeight: 20 }   // room to drop when the bank is short
      }
      QsDragArea { host: root; anchors.fill: parent; from: bankCol; onTap: id => root.add(id) }
      }
    }
  }

  }
  // ---- mouse drag: press an item (preview or bank) and move it: onto another item = before / after it, into the Text or the
  // Tiles part of the plate = that look (a tile-only item stays a tile), onto the bank = off. A press without moving = pick / add.
  property string dragId: ""
  property point dragPt: Qt.point(0, 0)
  property string dropZone: ""            // "" | text | tile | off
  property string dropOn: ""              // the item it lands next to
  property bool dropBefore: true
  property int dropNewRow: -1             // tiles: a new row at this index
  property rect dropRect: Qt.rect(0, 0, 0, 0)
  function hitIn(c, x, y) {   // the deepest item with a `tid` under (x, y) of container c
    let it = c, p = Qt.point(x, y), found = null;
    for (let n = 0; n < 30; n++) { const ch = it.childAt(p.x, p.y); if (!ch) break; p = it.mapToItem(ch, p.x, p.y); it = ch; if (it.tid !== undefined && it.tid !== "") found = it }
    return found;
  }
  function dragMove(pt) {   // pt in root coords
    dragPt = pt; dropOn = "";
    const pp = mapToItem(plate, pt.x, pt.y), pb = mapToItem(bankCol, pt.x, pt.y);
    if (pp.x >= 0 && pp.y >= 0 && pp.x <= plate.width && pp.y <= plate.height) {
      const pv = mapToItem(prev, pt.x, pt.y);
      dropZone = pv.y >= tilesCap.y - 3 ? "tile" : "text";
      const t = hitIn(prev, pv.x, pv.y);
      dropNewRow = -1;
      if (t && t.tid !== dragId) {
        const tl = t.mapFromItem(root, pt.x, pt.y), r = t.mapToItem(root, 0, 0);
        dropOn = t.tid; dropBefore = tl.x < t.width / 2;
        dropRect = Qt.rect(dropBefore ? r.x - 4 : r.x + t.width + 2, r.y, 2, t.height);
      } else if (dropZone === "tile") {   // not on a tile: in a row's band = the end of that row, in a gap / below = a new row there
        const rowsI = tilesCol.children.filter(c => c instanceof RowLayout && c.visible).sort((a, b) => a.y - b.y);
        const ty = mapToItem(tilesCol, pt.x, pt.y).y, o = tilesCol.mapToItem(root, 0, 0);
        let at = rowsI.length;
        for (let k = 0; k < rowsI.length; k++) {
          const ri = rowsI[k];
          if (ty >= ri.y + 4 && ty <= ri.y + ri.height - 4) { const last = ri.children.filter(c => c.tid).sort((a, b) => a.x - b.x).pop();
            if (last && last.tid !== dragId) { const r = last.mapToItem(root, 0, 0); dropOn = last.tid; dropBefore = false; dropRect = Qt.rect(r.x + last.width + 2, r.y, 2, last.height) } at = -1; break }
          if (ty < ri.y + 4) { at = k; break }
        }
        if (at >= 0) { dropNewRow = at; const y = at < rowsI.length ? rowsI[at].y - 4 : (rowsI.length ? rowsI[rowsI.length - 1].y + rowsI[rowsI.length - 1].height + 2 : 0);
                       dropRect = Qt.rect(o.x, o.y + y, tilesCol.width, 2) }
      }
    } else if (pb.x >= -8 && pb.y >= -8 && pb.x <= bankCol.width + 8 && pb.y <= bankCol.height + 8) dropZone = "off";
    else dropZone = "";
  }
  function drop() {
    const id = dragId, z = dropZone; dragId = ""; dropZone = "";
    if (!id || !z) return;
    sel = id;
    if (z === "off") { Tiles.setLook(id, "off"); return }
    const look = z === "tile" || Tiles.tileOnly(id) ? "widget" : "text";
    if (look === "widget") {   // tiles: into the row of the tile it was dropped on, or a new row
      const rows = Tiles.tileRowIds(widgets.filter(x => x !== id), prev.width, Math.round(38 * Theme.scale)).map(r => r.slice());
      if (dropOn) { const r = rows.findIndex(x => x.includes(dropOn)); if (r >= 0) rows[r].splice(rows[r].indexOf(dropOn) + (dropBefore ? 0 : 1), 0, id); else rows.push([id]) }
      else rows.splice(dropNewRow >= 0 ? dropNewRow : rows.length, 0, [id]);
      Tiles.setTileRows(rows);
      Tiles.setLook(id, "widget");
      return;
    }
    Tiles.setLook(id, look);
    const o = Tiles.flatten(Tiles.layoutRows).map(t => t.id).filter(x => x !== id && !!all[x]);
    let at = o.length;
    if (dropOn && o.includes(dropOn)) at = o.indexOf(dropOn) + (dropBefore ? 0 : 1);
    else { const same = o.filter(x => (Tiles.wideIds.includes(x)) === (look === "widget")); if (same.length) at = o.indexOf(same[same.length - 1]) + 1 }
    o.splice(at, 0, id);
    Tiles.setOrder(o);
  }
  Rectangle {   // where it lands
    z: 20; visible: !!root.dragId && (root.dropOn !== "" || root.dropNewRow >= 0)
    x: root.dropRect.x; y: root.dropRect.y; width: root.dropRect.width; height: root.dropRect.height; color: Theme.accent
  }
  Rectangle {   // the dragged item, under the cursor
    z: 21; visible: !!root.dragId
    x: root.dragPt.x + 10; y: root.dragPt.y + 6
    width: ghost.implicitWidth + 16; height: 22; radius: Theme.radiusInner
    color: Theme.container; border.width: 1; border.color: Theme.accent; opacity: 0.95
    Text { id: ghost; anchors.centerIn: parent; text: root.dragId ? root.nameOf(root.dragId) : ""; color: Theme.text
           font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(10 * Theme.scale) }
  }
}
