// Nothing-style history graph: dot-matrix columns, newest at the right edge. One or two series (0..1); the second one is dimmer and only
// shows above the first. A column over `hot` turns red. Fills its size: rows and columns follow the height / width.
// The faint background grid is a tiled picture (one texture); the canvas draws only the lit dots, so a 1 Hz repaint stays cheap.
import QtQuick
import qs.core

Item {
  id: g
  property var series: []        // 0..1, oldest first
  property var series2: []       // optional second series (dimmer)
  property int rev: 0            // bump to repaint (the arrays are replaced anyway)
  property real pitch: 6
  property real dot: 4
  property real hot: 0.9
  readonly property int rows: Math.max(1, Math.floor(height / pitch))
  readonly property int cols: Math.max(0, Math.floor(width / pitch))
  Image {   // the unlit dots
    anchors { left: parent.left; bottom: parent.bottom }
    width: g.cols * g.pitch; height: g.rows * g.pitch
    fillMode: Image.Tile; smooth: false
    source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='" + g.pitch + "' height='" + g.pitch + "'><circle cx='" + (g.dot / 2 + 1) + "' cy='" + (g.pitch - g.dot / 2 - 1) + "' r='" + (g.dot / 2)
            + "' fill='%23" + Theme.text.toString().slice(-6) + "' fill-opacity='0.14'/></svg>"
  }
  Canvas {
    id: cv
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections { target: g; function onSeriesChanged() { cv.requestPaint() } function onSeries2Changed() { cv.requestPaint() } function onRevChanged() { cv.requestPaint() } }
    Connections { target: Theme; function onTextChanged() { cv.requestPaint() } }
    onPaint: {   // lit dots only: three fills (second series / first / hot)
      const ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
      const rows = g.rows, cols = g.cols, n = g.series.length, n2 = g.series2.length, r = g.dot / 2, pitch = g.pitch, h = height;
      const paths = [[], [], []];   // 0 second, 1 lit, 2 hot
      for (let c = 0; c < cols; c++) {
        const k = n - cols + c, k2 = n2 - cols + c;
        const a = k >= 0 && k < n ? g.series[k] : -1, b = k2 >= 0 && k2 < n2 ? g.series2[k2] : -1;
        if (a <= 0 && b <= 0) continue;
        const hotCol = a > g.hot || b > g.hot, x = c * pitch + r + 1;
        for (let row = 0; row < rows; row++) {   // row 0 is the bottom
          const la = a * rows - row >= 0.5, lb = b * rows - row >= 0.5;
          if (!la && !lb) break;
          paths[hotCol ? 2 : la ? 1 : 0].push(x, h - row * pitch - r - 1);
        }
      }
      const style = [[Theme.text, 0.45], [Theme.text, 1], [Theme.red, 1]];
      for (let i = 0; i < 3; i++) {
        const pts = paths[i]; if (!pts.length) continue;
        ctx.globalAlpha = style[i][1]; ctx.fillStyle = style[i][0]; ctx.beginPath();
        for (let j = 0; j < pts.length; j += 2) { ctx.moveTo(pts[j] + r, pts[j + 1]); ctx.arc(pts[j], pts[j + 1], r, 0, Math.PI * 2) }
        ctx.fill();
      }
    }
  }
}
