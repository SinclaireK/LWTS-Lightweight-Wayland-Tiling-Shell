// Desktop icons (Work mode), KDE-style: the files / folders of the desktop folder (`Desk.dir`, ~/Desktop) lie straight on the desktop, no frame,
// plus a Trash icon. Cells are `Desk.iconPx` (small / medium / large) + gap. A file without a saved cell takes the first free one (column by
// column from the top-left); cells under widgets are never used. Drag moves the selection and snaps to the grid (all cells are then saved,
// so nothing jumps around); dropping on the Trash icon trashes. A rubber band on the bare desktop selects, Ctrl toggles. Double click
// opens, right click = item menu (Desk.itemMenuItems). Icons that do not fit the screen are not drawn (no scrolling).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.services
import qs.widgets

Item {
  id: lay
  property var widgets: []                 // placements shown on this output (their rectangles are blocked)
  signal itemMenu(real x, real y)
  // Cells sit on the wallpaper's dot lattice (Desk.ox / oy are dots, the pitch is 3 / 4 / 5 dots); the icon box is inset by gap / 2 inside its cell.
  readonly property int sz: Desk.iconPx
  readonly property int pitch: Desk.iconPitch
  readonly property int rows: Math.max(1, Math.floor((height - Desk.oy - 24) / pitch))
  readonly property int cols: Math.max(1, Math.floor((width - Desk.ox) / pitch))
  readonly property string trashKey: "\u0001trash"
  function cellPx(c, r) { return Qt.point(Desk.ox + c * pitch + Desk.inset, Desk.oy + r * pitch + Desk.inset) }   // top-left of the icon box
  function cellAt(px, py) { return [Math.floor((px - Desk.ox) / pitch), Math.floor((py - Desk.oy) / pitch)] }
  function inGrid(c, r) { return c >= 0 && r >= 0 && c < cols && r < rows }
  function blocked(c, r) {                 // does a widget cover this icon cell?
    const x = cellPx(c, r).x, y = cellPx(c, r).y;
    for (const p of widgets) {
      const wx = Desk.ox + Desk.pos(p.x) + Desk.inset, wy = Desk.oy + Desk.pos(p.y) + Desk.inset;
      if (x < wx + Desk.px(p.w) && x + sz > wx && y < wy + Desk.px(p.h) && y + sz > wy) return true;
    }
    return false;
  }

  property var entries: []                 // [{ name, label, path, isDir, ext }]: the files in the model's order, the Trash last
  function rebuild() {
    const a = [];
    for (let i = 0; i < list.count; i++) { const n = list.get(i, "fileName"); a.push({ name: n, label: n, path: list.get(i, "filePath"), isDir: list.get(i, "fileIsDir"), ext: list.get(i, "fileSuffix") }) }
    a.push({ name: trashKey, label: "Trash", path: Desk.trashPath, isDir: false, ext: "", trash: true });
    entries = a;
    meta.running = false; meta.running = true;
    Desk.selection = Desk.selection.filter(p => a.some(e => e.path === p));   // renamed / removed ones leave the selection
  }
  FolderListModel {
    id: list
    folder: "file://" + Desk.dir
    showDirs: true; showDirsFirst: true; showDotAndDotDot: false; showHidden: false
    sortField: Desk.iconSort === "type" ? FolderListModel.Type : Desk.iconSort === "date" ? FolderListModel.Time : FolderListModel.Name
    sortReversed: Desk.iconSort === "date"   // newest first
    onCountChanged: later.restart()
    onStatusChanged: later.restart()
  }
  FolderListModel {   // the trash: only its count matters (empty / full icon)
    id: trashList
    folder: "file://" + Quickshell.env("HOME") + "/.local/share/Trash/files"
    showDirs: true; showDotAndDotDot: false; showHidden: true
    onCountChanged: Desk.trashFull = count > 0
    Component.onCompleted: Desk.trashFull = count > 0
  }
  property var iconNames: ({})             // .desktop file -> its Icon=
  property var links: ({})                 // symbolic links (badge)
  Process {
    id: meta
    command: ["luajit", Quickshell.shellDir + "/scripts/desk-meta.lua", Desk.dir]
    stdout: StdioCollector {
      onStreamFinished: {
        const ic = {}, ln = {};
        for (const l of text.split("\n")) { const f = l.split("\t"); if (f[0] === "icon" && f.length >= 3) ic[f[1]] = f[2]; else if (f[0] === "link") ln[f[1]] = true }
        lay.iconNames = ic; lay.links = ln;
      }
    }
  }
  Connections { target: list; function onDataChanged() { later.restart() } function onModelReset() { later.restart() } function onRowsInserted() { later.restart() } function onRowsRemoved() { later.restart() } }
  Timer { id: later; interval: 60; onTriggered: lay.rebuild() }
  Component.onCompleted: rebuild()

  function layout(es, saved) {             // name -> [col, row]
    const used = {}, out = {};
    for (const e of es) {
      const s = saved[e.name] || (e.trash ? [cols - 1, rows - 1] : null);   // the Trash waits in the bottom right corner
      if (s && inGrid(s[0], s[1]) && !used[s[0] + "," + s[1]] && !blocked(s[0], s[1])) { out[e.name] = s; used[s[0] + "," + s[1]] = true }
    }
    let c = 0, r = 0;
    for (const e of es) {
      if (out[e.name]) continue;
      while (c < cols && (used[c + "," + r] || blocked(c, r))) { r++; if (r >= rows) { r = 0; c++ } }
      if (c >= cols) break;                // does not fit: not drawn
      out[e.name] = [c, r]; used[c + "," + r] = true;
    }
    return out;
  }
  readonly property var cells: layout(entries, Desk.iconPos, widgets, sz, rows, cols)   // the extra arguments only make the binding follow them

  // ---- drag of the selection ----
  property bool dragging: false
  property real dragDx: 0
  property real dragDy: 0
  property var dragSet: []                 // paths that move
  property string dragLead: ""
  property var dropCell: null              // [col, row] of the lead while dragging (preview), null when the drop would not fit
  function entryOf(path) { return entries.find(x => x.path === path) }
  // -> { trash: true } (dropped on the Trash), { name: [c, r] } for the moved ones, or null when it does not fit
  function planDrop() {
    const lead = entryOf(dragLead); if (!lead || !cells[lead.name]) return null;
    const lp = cellPx(cells[lead.name][0], cells[lead.name][1]);
    const t = cellAt(lp.x + sz / 2 + dragDx, lp.y + sz / 2 + dragDy);
    const tc = cells[trashKey];
    if (tc && t[0] === tc[0] && t[1] === tc[1] && !dragSet.includes(Desk.trashPath)) return { trash: true };
    const dc = t[0] - cells[lead.name][0], dr = t[1] - cells[lead.name][1];
    const moving = {}, occupied = {};
    for (const p of dragSet) { const e = entryOf(p); if (e) moving[e.name] = true }
    for (const e of entries) if (!moving[e.name] && cells[e.name]) occupied[cells[e.name][0] + "," + cells[e.name][1]] = true;
    const plan = {};
    for (const n of Object.keys(moving)) {
      const c = cells[n]; if (!c) return null;
      const nc = c[0] + dc, nr = c[1] + dr;
      if (!inGrid(nc, nr) || occupied[nc + "," + nr] || blocked(nc, nr)) return null;
      plan[n] = [nc, nr];
    }
    return plan;
  }
  function endDrag(commit) {
    if (commit) {
      const plan = planDrop();
      if (plan && plan.trash) { Desk.selection = dragSet.filter(p => p !== Desk.trashPath); Desk.trashSelection() }
      else if (plan) { const all = {}; for (const n of Object.keys(cells)) all[n] = cells[n]; for (const n of Object.keys(plan)) all[n] = plan[n]; Desk.savePositions(all) }
    }
    dragging = false; dragDx = 0; dragDy = 0; dropCell = null; dragSet = []; dragLead = "";
  }

  // ---- rubber band on the bare desktop ----
  property bool banding: false
  property point bandA: Qt.point(0, 0)
  property point bandB: Qt.point(0, 0)
  property var bandBase: []
  readonly property rect bandRect: Qt.rect(Math.min(bandA.x, bandB.x), Math.min(bandA.y, bandB.y), Math.abs(bandA.x - bandB.x), Math.abs(bandA.y - bandB.y))
  function bandSelect() {
    const r = bandRect, hit = [];
    for (const e of entries) {
      const c = cells[e.name]; if (!c) continue;
      const p = cellPx(c[0], c[1]);
      if (p.x < r.x + r.width && p.x + sz > r.x && p.y < r.y + r.height && p.y + sz > r.y) hit.push(e.path);
    }
    Desk.selection = bandBase.concat(hit.filter(h => !bandBase.includes(h)));
  }
  MouseArea {
    anchors.fill: parent; acceptedButtons: Qt.LeftButton   // right click passes on to the desktop menu
    onPressed: m => { lay.banding = true; lay.bandA = Qt.point(m.x, m.y); lay.bandB = lay.bandA; lay.bandBase = (m.modifiers & Qt.ControlModifier) ? Desk.selection : []; if (!(m.modifiers & Qt.ControlModifier)) Desk.selection = [] }
    onPositionChanged: m => { if (lay.banding) { lay.bandB = Qt.point(m.x, m.y); lay.bandSelect() } }
    onReleased: lay.banding = false
    onCanceled: lay.banding = false
  }
  Rectangle {
    visible: lay.banding && (lay.bandRect.width > 3 || lay.bandRect.height > 3)
    x: lay.bandRect.x; y: lay.bandRect.y; width: lay.bandRect.width; height: lay.bandRect.height
    color: Theme.fill; border.color: Theme.edge; border.width: 1
  }

  // Papirus mimetype / places icon names by kind (the icon theme is Papirus-Dark, see icon_theme in settings.toml)
  readonly property var extIcons: ({
    png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic", webp: "image-x-generic", gif: "image-x-generic", svg: "image-x-generic", bmp: "image-x-generic",
    mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", avi: "video-x-generic", mov: "video-x-generic",
    mp3: "audio-x-generic", flac: "audio-x-generic", ogg: "audio-x-generic", wav: "audio-x-generic", opus: "audio-x-generic", m4a: "audio-x-generic",
    zip: "application-zip", "7z": "application-7zip", rar: "application-x-rar", tar: "application-x-tar", gz: "application-gzip", xz: "package-x-generic", zst: "package-x-generic",
    pdf: "application-pdf", doc: "x-office-document", docx: "x-office-document", odt: "x-office-document", rtf: "x-office-document",
    xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", ods: "x-office-spreadsheet", csv: "text-csv", ppt: "x-office-presentation", pptx: "x-office-presentation", odp: "x-office-presentation",
    txt: "text-x-generic", log: "text-x-log", md: "text-markdown", json: "application-json", html: "text-html", htm: "text-html",
    py: "text-x-python", lua: "text-x-lua", sh: "application-x-shellscript", js: "text-x-script", qml: "text-x-script", rs: "text-x-script", c: "text-x-csrc", h: "text-x-csrc",
    css: "text-x-script", toml: "text-x-script", appimage: "application-x-executable"
  })
  function iconName(e) {
    if (e.trash) return Desk.trashFull ? "user-trash-full" : "user-trash";
    if (e.isDir) return "folder";
    if (e.ext === "desktop") return iconNames[e.name] || "application-x-executable";
    return extIcons[(e.ext || "").toLowerCase()] || "text-x-generic";
  }
  function iconSource(name) { return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, "text-x-generic") }

  Rectangle {   // where the drag would land
    visible: lay.dragging && !!lay.dropCell
    x: lay.dropCell ? lay.cellPx(lay.dropCell[0], lay.dropCell[1]).x : 0; y: lay.dropCell ? lay.cellPx(lay.dropCell[0], lay.dropCell[1]).y : 0
    width: lay.sz; height: lay.sz; radius: Theme.radiusInner; color: "transparent"; border.color: Theme.edge; border.width: 1
  }

  Repeater {
    model: lay.entries
    Item {
      id: e
      required property var modelData
      readonly property var cell: lay.cells[modelData.name]
      readonly property bool picked: Desk.isSel(modelData.path)
      readonly property bool moving: lay.dragging && lay.dragSet.includes(modelData.path)
      readonly property bool trashHot: !!modelData.trash && lay.dragging && !!lay.dropCell && !!lay.cells[lay.trashKey]
                                       && lay.dropCell[0] === lay.cells[lay.trashKey][0] && lay.dropCell[1] === lay.cells[lay.trashKey][1]
      visible: !!cell
      x: (cell ? lay.cellPx(cell[0], cell[1]).x : 0) + (moving ? lay.dragDx : 0)
      y: (cell ? lay.cellPx(cell[0], cell[1]).y : 0) + (moving ? lay.dragDy : 0)
      z: moving ? 10 : 0
      opacity: moving ? 0.85 : 1
      width: lay.sz; height: lay.sz
      Rectangle {
        anchors.fill: parent; radius: Theme.radiusInner
        color: e.picked || e.trashHot ? Theme.fillHover : ma.containsMouse ? Theme.fill : "transparent"
        border.color: e.picked || e.trashHot ? Theme.edge : "transparent"; border.width: 1
      }
      // layout: the label sits at the very bottom of the cell, the icon is centred in what is left above it
      readonly property int fontPx: Math.round((lay.sz >= 72 ? 11 : lay.sz >= 56 ? 10 : 9) * Theme.scale)
      readonly property int lines: lay.sz >= 56 ? 2 : 1
      readonly property int labelH: Math.round(fontPx * 1.25 * lines)
      readonly property int box: Math.max(16, lay.sz - labelH - 10)
      Item {
        id: glyph
        x: (parent.width - e.box) / 2; y: 4 + (parent.height - e.labelH - 10 - e.box) / 2; width: e.box; height: e.box
        Image {
          anchors.fill: parent; visible: Desk.iconColored; asynchronous: true; smooth: true; fillMode: Image.PreserveAspectFit
          sourceSize: Qt.size(e.box * 2, e.box * 2)
          source: Desk.iconColored ? lay.iconSource(lay.iconName(e.modelData)) : ""
        }
        AppIcon { anchors.fill: parent; visible: !Desk.iconColored; size: e.box; source: Desk.iconColored ? "" : lay.iconSource(lay.iconName(e.modelData)) }
        Rectangle {   // link badge (symbolic link)
          visible: !!lay.links[e.modelData.name]
          x: -2; y: parent.height - 11; width: 13; height: 13; radius: 4; color: Theme.surface; border.color: Theme.edge; border.width: 1
          Icon { anchors.centerIn: parent; name: "arrow-square-out"; font.pixelSize: 9; color: Theme.text }
        }
      }
      Text {
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3; anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 4; height: e.labelH
        text: e.modelData.ext === "desktop" ? e.modelData.label.replace(/\.desktop$/, "") : e.modelData.label
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignBottom
        wrapMode: Text.WrapAnywhere; elide: Text.ElideRight; maximumLineCount: e.lines
        color: Theme.text; font.family: Theme.font; font.pixelSize: e.fontPx
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.55)   // readable on any wallpaper
      }
      MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point start; property bool pressedLeft: false; property bool toggledOff: false
        onPressed: m => {
          const ctrl = m.modifiers & Qt.ControlModifier;
          start = mapToItem(lay, m.x, m.y); toggledOff = false;
          if (m.button === Qt.RightButton) { if (!e.picked) Desk.selection = [e.modelData.path]; return }
          pressedLeft = true;
          if (ctrl) { if (e.picked) toggledOff = true; else Desk.selection = Desk.selection.concat([e.modelData.path]) }
          else if (!e.picked) Desk.selection = [e.modelData.path];
        }
        onPositionChanged: m => {
          if (!pressedLeft || Desk.iconsLocked) return;
          const p = mapToItem(lay, m.x, m.y), dx = p.x - start.x, dy = p.y - start.y;
          if (!lay.dragging) {
            if (Math.abs(dx) + Math.abs(dy) < 8) return;
            if (!e.picked) Desk.selection = [e.modelData.path];
            lay.dragSet = Desk.selection; lay.dragLead = e.modelData.path; lay.dragging = true;
          }
          lay.dragDx = dx; lay.dragDy = dy;
          const plan = lay.planDrop(); const n = e.modelData.name;
          lay.dropCell = plan && plan.trash ? lay.cells[lay.trashKey] : plan && plan[n] ? plan[n] : null;
        }
        onReleased: m => {
          pressedLeft = false;
          if (lay.dragging) { lay.endDrag(true); return }
          if (m.button === Qt.LeftButton) {
            if (toggledOff) Desk.selection = Desk.selection.filter(p => p !== e.modelData.path);
            else if (!(m.modifiers & Qt.ControlModifier)) Desk.selection = [e.modelData.path];   // plain click on a member of a group keeps only it
          }
        }
        onClicked: m => { if (m.button === Qt.RightButton) { const p = mapToItem(lay, m.x, m.y); lay.itemMenu(p.x, p.y) } }
        onDoubleClicked: m => { if (m.button === Qt.LeftButton && !(m.modifiers & Qt.ControlModifier)) { Desk.selection = [e.modelData.path]; Desk.openSelection() } }
        onCanceled: { pressedLeft = false; if (lay.dragging) lay.endDrag(false) }
      }
    }
  }
}
