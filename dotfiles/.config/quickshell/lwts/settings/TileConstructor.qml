// Quick settings grid constructor (settings_spec 2.1-2.2): the SAME tiles as the real Super+Space popup - a direct
// status is live, but a click here NEVER acts on a tile (it only selects / drops); the corner controls and the bank edit the layout.
// Mouse: drag a tile (or a tile from the bank) - an accent bar shows where it lands: between tiles of a row, or a line
// between rows for a NEW row; drop on the bank to remove it. A plain click only selects the tile. Hover shows x / resize.
// Keyboard (forwarded by SettingsNew.qml while this row has focus): ← ↑ → ↓ move focus across the real packed rows,
// into the bank and back; Space grabs the focused tile, arrows then move it, Enter / Esc let go; W toggles
// text <-> widget (how the launcher shows it); 1-9 drops a grabbed tile at that exact position; Delete / Backspace sends it to the bank;
// Enter on a bank tile appends it at the end.
import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.widgets

Item {
  id: root
  implicitHeight: col.implicitHeight

  property int focusIndex: 0
  property bool grabbed: false

  readonly property var activeList: Tiles.flatten(Tiles.layoutRows).map(t => ({ id: t.id, wide: t.wide }))   // in row order
  readonly property var bankIds: Tiles.bank                  // [id, ...]
  readonly property var rows: Tiles.layoutRows               // the exact rows the real popup renders
  readonly property int activeCount: activeList.length
  readonly property var flat: activeList.concat(bankIds.map(id => ({ id, wide: false })))
  readonly property bool focusInBank: focusIndex >= activeCount
  readonly property var focusItem: flat[clamp(focusIndex)] || null

  function clamp(i) { return Math.max(0, Math.min(flat.length - 1, i)) }
  function isCustom(id) { return Tiles.customPresets.some(p => p.id === id) }
  function posOf(idx) { let i = idx; for (let r = 0; r < rows.length; r++) { if (i < rows[r].length) return { r, c: i }; i -= rows[r].length } return null }
  function idxOf(r, c) { let i = 0; for (let rr = 0; rr < r; rr++) i += rows[rr].length; return i + Math.max(0, Math.min(rows[r].length - 1, c)) }

  function moveTo(target) {   // grabbed tile -> an exact position in activeList (also used by 1-9)
    if (focusInBank || !grabbed) return;
    const to = Math.max(0, Math.min(activeCount - 1, target));
    Tiles.moveTile(focusIndex, to);
    focusIndex = to;
  }

  function stepFocus(dr, dc) {   // one geometric step; false at an edge hands the key back to the settings list
    if (!focusInBank) {
      const p = posOf(focusIndex);
      let r = p.r + dr, c = p.c + dc;
      if (dc !== 0) {   // left/right: wrap into the next/previous row, or into the bank past the last row
        if (c < 0) { r--; c = r >= 0 ? rows[r].length - 1 : 0 }
        else if (c >= (rows[p.r] || []).length) { r++; c = 0 }
      }
      if (r < 0) return false;
      if (r >= rows.length) { if (bankIds.length === 0) return false; if (grabbed) return false; focusIndex = activeCount; return true }
      const idx = idxOf(r, c);
      if (grabbed) moveTo(idx); else focusIndex = idx;
      return true;
    }
    if (grabbed) return false;   // bank tiles are not reorderable, only addable
    if (dr < 0) { focusIndex = rows.length ? idxOf(rows.length - 1, 0) : 0; return true }
    if (dr > 0) return false;
    const next = focusIndex + dc;
    if (next < activeCount || next >= flat.length) return false;
    focusIndex = next;
    return true;
  }

  function handleKey(e) {
    const k = e.key;
    if (flat.length === 0) return false;
    if (k === Qt.Key_Space && !focusInBank) { grabbed = !grabbed; return true }
    if (k >= Qt.Key_1 && k <= Qt.Key_9 && grabbed) { moveTo(k - Qt.Key_1); return true }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && grabbed) { grabbed = false; return true }
    if (k === Qt.Key_Escape && grabbed) { grabbed = false; return true }
    if (k === Qt.Key_Left) return stepFocus(0, -1);
    if (k === Qt.Key_Right) return stepFocus(0, 1);
    if (k === Qt.Key_Up) return stepFocus(-1, 0);
    if (k === Qt.Key_Down) return stepFocus(1, 0);
    if (k === Qt.Key_W && !focusInBank && !grabbed) { Tiles.toggleWide(focusItem.id); return true }
    if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && !focusInBank) {
      Tiles.removeTile(focusItem.id); grabbed = false; focusIndex = clamp(focusIndex); return true;
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && focusInBank) {
      Tiles.addTile(focusItem.id); focusIndex = clamp(activeCount - 1); return true;
    }
    return false;
  }

  function grip(idx) {   // mouse equivalent of Space: click a grip to grab, click another tile to drop it
    if (idx >= activeCount) return;
    if (grabbed && focusIndex === idx) { grabbed = false; return }
    if (grabbed) { moveTo(idx); grabbed = false; return }
    focusIndex = idx; grabbed = true;
  }
  function tap(idx) {   // click on the tile body: drop if grabbed, else just select (a tile must never fire while arranging); a bank tile is added
    if (grabbed) { if (idx < activeCount) moveTo(idx); grabbed = false; return }
    focusIndex = idx;
    if (idx >= activeCount) Tiles.addTile(flat[idx].id);
  }

  Column {
    id: col
    width: parent.width
    spacing: 10

    Flow {   // presets (settings_spec 2.3): factory + custom, switch with one click; no rename UI yet (no text
             // input widget in this menu to drive it from) - custom presets get an auto name, delete only.
      width: parent.width
      spacing: 6
      Repeater {
        model: Tiles.presets
        Row {
          required property var modelData
          spacing: 2
          Rectangle {
            width: label.implicitWidth + 16; height: 24
            radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge
            Label { id: label; anchors.centerIn: parent; text: parent.parent.modelData.label }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Tiles.applyPreset(parent.parent.modelData.id) }
          }
          MouseArea {   // custom presets only: delete
            visible: root.isCustom(modelData.id)
            width: 18; height: 24
            cursorShape: Qt.PointingHandCursor
            onClicked: Tiles.deleteCustomPreset(modelData.id)
            Icon { anchors.centerIn: parent; name: "x"; color: Theme.dim }
          }
        }
      }
      Rectangle {   // + save current layout as a new preset
        width: saveLabel.implicitWidth + 16; height: 24
        radius: Theme.radiusCtl; color: "transparent"; border.width: 1; border.color: Theme.edge
        Label { id: saveLabel; anchors.centerIn: parent; text: "+ Save current" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: Tiles.saveCustomPreset("Custom " + (Tiles.customPresets.length + 1)) }
      }
    }

    Item {   // the grid: exactly what Super+Space renders, rows you can drag tiles between
      id: grid
      width: parent.width
      height: rowsCol.height + (root.activeCount === 0 ? 56 : 0)
      Column {
        id: rowsCol
        width: parent.width
        spacing: 6
        Repeater {
          id: rowsRep
          model: root.rows
          Rectangle {
            id: rowVis
            required property var modelData
            required property int index
            readonly property int rowStart: { let n = 0; for (let r = 0; r < index; r++) n += root.rows[r].length; return n }
            width: rowsCol.width; height: tilesRow.height + 10
            radius: Theme.radiusCard; color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
            property alias tilesRep: tilesRep
            Row {
              id: tilesRow
              x: 5; y: 5; width: parent.width - 10; spacing: 6
              readonly property int totalSlots: rowVis.modelData.reduce((a, t) => a + t.slots, 0)
              readonly property real unit: (width - spacing * (rowVis.modelData.length - 1)) / Math.max(1, totalSlots)
              Repeater {
                id: tilesRep
                model: rowVis.modelData
                Item {
                  id: cell
                  required property var modelData
                  required property int index
                  readonly property int flatIdx: rowVis.rowStart + index
                  readonly property var t: Tiles.all[modelData.id]
                  readonly property bool lifted: root.dragId === modelData.id
                  width: tilesRow.unit * modelData.slots
                  height: tile.height
                  opacity: lifted ? 0.35 : 1
                  Tile {
                    id: tile
                    width: parent.width
                    wide: cell.modelData.wide
                    enabled: false   // the drag area below owns the mouse; this is only the picture
                    icon: cell.t.icon; label: cell.t.label(); status: cell.t.status ? cell.t.status() : ""; on: cell.t.on(); progress: cell.t.progress ? cell.t.progress() : -1
                    focused: root.focusIndex === cell.flatIdx
                  }
                  Rectangle {   // grabbed highlight (space)
                    visible: root.grabbed && root.focusIndex === cell.flatIdx
                    anchors.fill: tile; radius: Theme.radiusCard; color: "transparent"
                    border.width: 2; border.color: Theme.accent
                  }
                  HoverHandler { id: cellHover }   // not drag.containsMouse: the corner controls are children, they took the hover from `drag` and the controls blinked
                  MouseArea {
                    id: drag
                    anchors.fill: parent
                    cursorShape: root.dragId ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point start
                    property bool moved: false
                    onPressed: m => { start = Qt.point(m.x, m.y); moved = false; root.focusIndex = cell.flatIdx }
                    onPositionChanged: m => {
                      if (!pressed) return;
                      if (!moved && Math.hypot(m.x - start.x, m.y - start.y) > 8) { moved = true; root.beginDrag(cell.modelData.id) }
                      if (moved) root.dragTo(drag.mapToItem(root, m.x, m.y))
                    }
                    onReleased: m => { if (moved) root.endDrag(); else root.tap(cell.flatIdx) }
                    onCanceled: root.cancelDrag()
                  }
                  Row {   // hover controls: resize and remove
                    visible: cellHover.hovered && !root.dragId
                    anchors { top: parent.top; right: parent.right; margins: 2 }
                    spacing: 2
                    MouseArea { width: 16; height: 16; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Tiles.toggleWide(cell.modelData.id)
                                Icon { anchors.centerIn: parent; name: "arrows-out-simple"; color: parent.containsMouse ? Theme.accent : Theme.dim } }
                    MouseArea { width: 16; height: 16; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Tiles.removeTile(cell.modelData.id)
                                Icon { anchors.centerIn: parent; name: "x"; color: parent.containsMouse ? Theme.red : Theme.dim } }
                  }
                }
              }
            }
          }
        }
      }
      Rectangle {   // empty grid: a place to drop the first tile
        visible: root.activeCount === 0
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56; radius: Theme.radiusCard; color: "transparent"; border.width: 1; border.color: Theme.line
      }
      Rectangle {   // where the dragged tile lands
        id: bar
        visible: root.dragId !== "" && root.drop !== null
        color: Theme.accent; radius: 2
        x: root.dropRect.x; y: root.dropRect.y; width: root.dropRect.w; height: root.dropRect.h
      }
    }

    Text {   // keyboard reorder hint (the keys exist, nobody found them)
      width: parent.width
      wrapMode: Text.WordWrap
      color: root.grabbed ? Theme.accent : Theme.dim
      font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale)
      text: root.grabbed ? "Moving: ← ↑ → ↓ move · 1-9 exact place · Enter / Esc drop · Delete remove"
                         : "Order of the launcher items (Text / Widget is set in Toggles and Info). Keyboard: ← ↑ → ↓ pick · Space grab · W text / widget · Delete remove · Enter on a bank tile adds it. Mouse: drag, a click only selects."
    }

    Column {   // bank: tiles that are off; click or drag them into the grid
      id: bankCol
      width: parent.width
      spacing: 4
      visible: root.bankIds.length > 0 || root.dragId !== ""
      Label { text: root.dragId && root.overBank ? "Drop here to remove" : "Bank"; color: root.dragId && root.overBank ? Theme.red : Theme.dim; font.weight: Font.DemiBold; font.pixelSize: Math.round(11 * Theme.scale) }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: root.bankIds
          Item {
            id: bt
            required property string modelData
            required property int index
            readonly property int flatIdx: root.activeCount + index
            readonly property var t: Tiles.all[modelData]
            width: Math.ceil(bankText.advanceWidth) + 62; height: 30   // whole name + the "+" (no elided labels)
            TextMetrics { id: bankText; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale); text: bt.t.label() }
            opacity: root.dragId === modelData ? 0.35 : 1
            Tile {
              anchors.fill: parent
              wide: true; enabled: false
              icon: bt.t.icon; label: bt.t.label(); on: false
              focused: root.focusIndex === bt.flatIdx
            }
            Icon { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 } name: "plus"; color: Theme.dim }
            MouseArea {
              id: bdrag
              anchors.fill: parent
              cursorShape: root.dragId ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              property point start
              property bool moved: false
              onPressed: m => { start = Qt.point(m.x, m.y); moved = false; root.focusIndex = bt.flatIdx }
              onPositionChanged: m => {
                if (!pressed) return;
                if (!moved && Math.hypot(m.x - start.x, m.y - start.y) > 8) { moved = true; root.beginDrag(bt.modelData) }
                if (moved) root.dragTo(bdrag.mapToItem(root, m.x, m.y))
              }
              onReleased: m => { if (moved) root.endDrag(); else root.tap(bt.flatIdx) }
              onCanceled: root.cancelDrag()
            }
          }
        }
      }
    }
  }

  // ---- mouse drag: pick up, show where it lands, drop --------------------------------------------------------------
  property string dragId: ""
  property var drop: null            // { row, col, newRow } in the grid, or null
  property bool overBank: false
  property point ghostAt: Qt.point(0, 0)
  readonly property var dropRect: {   // the accent bar for `drop`, in grid coordinates
    const d = drop; if (!d) return { x: 0, y: 0, w: 0, h: 0 };
    const n = rowsRep.count;
    if (d.newRow) { const it = d.row < n ? rowsRep.itemAt(d.row) : null, last = n ? rowsRep.itemAt(n - 1) : null;
                    return { x: 0, y: it ? it.y - 5 : last ? last.y + last.height + 1 : 0, w: grid.width, h: 3 } }
    const rv = rowsRep.itemAt(d.row); if (!rv) return { x: 0, y: 0, w: 0, h: 0 };
    const tr = rv.tilesRep, k = tr.count;
    const x = k === 0 ? 6 : d.col < k ? tr.itemAt(d.col).x + 5 - 5 : tr.itemAt(k - 1).x + tr.itemAt(k - 1).width + 5;
    return { x: x, y: rv.y + 5, w: 3, h: rv.height - 10 };
  }
  function beginDrag(id) { dragId = id; grabbed = false }
  function dragTo(p) {   // p in root coordinates
    ghostAt = p;
    const g = grid.mapFromItem(root, p.x, p.y), b = bankCol.mapFromItem(root, p.x, p.y);
    overBank = bankCol.visible && b.y >= 0 && b.y <= bankCol.height && b.x >= 0 && b.x <= bankCol.width && activeIdSet(dragId);
    if (overBank || g.y < -14 || g.y > grid.height + 14) { drop = null; return }
    const n = rowsRep.count;
    if (n === 0) { drop = { row: 0, col: 0, newRow: true }; return }
    for (let r = 0; r < n; r++) {
      const it = rowsRep.itemAt(r);
      if (g.y < it.y + 7 && g.y >= it.y - 10) { drop = { row: r, col: 0, newRow: true }; return }
      if (g.y >= it.y && g.y <= it.y + it.height) {
        const tr = it.tilesRep; let col = tr.count;
        for (let c = 0; c < tr.count; c++) { const ti = tr.itemAt(c); if (g.x < it.x + ti.x + ti.width / 2) { col = c; break } }
        drop = { row: r, col, newRow: false }; return
      }
    }
    const last = rowsRep.itemAt(n - 1);
    drop = g.y > last.y + last.height - 6 ? { row: n, col: 0, newRow: true } : null;
  }
  function activeIdSet(id) { return activeList.some(t => t.id === id) }
  function endDrag() {
    const id = dragId, d = drop, rm = overBank;
    cancelDrag();
    if (!id) return;
    if (rm) { Tiles.removeTile(id); return }
    if (d) Tiles.placeTile(id, d.row, d.col, d.newRow);
  }
  function cancelDrag() { dragId = ""; drop = null; overBank = false }
  MouseArea {   // one cursor for the whole drag: gaps between tiles / rows have no MouseArea, the cursor fell back to the arrow there
    anchors.fill: parent
    z: 49
    visible: root.dragId !== ""
    acceptedButtons: Qt.NoButton
    cursorShape: Qt.ClosedHandCursor
  }
  Rectangle {   // the tile in the hand
    visible: root.dragId !== ""
    z: 50
    x: root.ghostAt.x - width / 2; y: root.ghostAt.y - height / 2
    width: 150; height: Math.round(34 * Theme.scale); radius: Theme.radius
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95); border.width: 1; border.color: Theme.accent
    Row { anchors.centerIn: parent; spacing: 7
          Icon { name: root.dragId && Tiles.all[root.dragId] ? Tiles.all[root.dragId].icon : ""; color: Theme.accent }
          Label { text: root.dragId && Tiles.all[root.dragId] ? Tiles.all[root.dragId].label() : "" } }
  }

  component Label: Text { color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale) }
}
