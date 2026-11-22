// Mouse layer of the Layout constructor (QsConstructor = `host`) over the preview / the bank: it owns the mouse, the pieces
// under it are only pictures. Press + move = drag (host.dragMove / host.drop); press without moving = tap(id).
import QtQuick

MouseArea {
  property Item host
  property Item from
  signal tap(string id)
  z: 10
  cursorShape: host.dragId ? Qt.ClosedHandCursor : Qt.PointingHandCursor
  preventStealing: true
  property point start
  property string pid: ""
  onPressed: m => { start = Qt.point(m.x, m.y); const p = mapToItem(from, m.x, m.y), t = host.hitIn(from, p.x, p.y); pid = t ? t.tid : "" }
  onPositionChanged: m => {
    if (!host.dragId && pid && Math.hypot(m.x - start.x, m.y - start.y) > 6) { host.dragId = pid; host.grabbed = false }
    if (host.dragId) host.dragMove(mapToItem(host, m.x, m.y));
  }
  onReleased: { if (host.dragId) host.drop(); else if (pid) tap(pid); pid = "" }
  onCanceled: { host.dragId = ""; host.dropZone = ""; pid = "" }
}
