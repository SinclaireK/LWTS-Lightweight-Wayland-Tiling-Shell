.pragma library
// Keyboard for the bar drops built from list rows (Audio, Network, Bluetooth). A row is any visible item that has a
// `focused` property and an `act` signal (ListRow, AudioPanel's VolRow); one with `nudge(d)` also takes ← → (volume).
// Keys: ↑ ↓ pick (the first press picks the first / last row), Enter / Space act. Esc is the panel's own.

function rows(root) {
  const out = [];
  (function walk(it) {
    for (const c of it.children) {
      if (c.visible && c.focused !== undefined && typeof c.act === "function") out.push(c);
      walk(c);
    }
  })(root);
  out.sort((a, b) => a.mapToItem(root, 0, 0).y - b.mapToItem(root, 0, 0).y);
  return out;
}

function handle(root, e) {   // true = key used
  const list = rows(root);
  if (!list.length) return false;
  const cur = list.findIndex(r => r.focused);
  const k = e.key;
  if (k === Qt.Key_Down || k === Qt.Key_Up) {
    const next = cur < 0 ? (k === Qt.Key_Down ? 0 : list.length - 1) : (cur + (k === Qt.Key_Down ? 1 : -1) + list.length) % list.length;
    if (cur >= 0) list[cur].focused = false;
    list[next].focused = true;
    return true;
  }
  if (cur < 0) return false;
  if (typeof list[cur].keyed === "function" && list[cur].keyed(k)) return true;   // row's own keys (notification: Delete, M)
  if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (!e.isAutoRepeat) list[cur].act(); return true }
  if ((k === Qt.Key_Left || k === Qt.Key_Right) && typeof list[cur].nudge === "function") { list[cur].nudge(k === Qt.Key_Right ? 0.05 : -0.05); return true }
  return false;
}
