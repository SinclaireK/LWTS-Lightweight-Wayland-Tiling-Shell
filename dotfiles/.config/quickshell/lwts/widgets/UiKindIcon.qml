// An app kind as a 7x7 dot-matrix glyph (browser, terminal, game, chat, video, music, editor, code, files, system, office, graphics, network, ai, other).
// `kind` from services/Kinds.qml (Kinds.ofProcess(name) / Kinds.ofEntry(desktopEntry)). `dot` + `gap` set the size (2 + 1 = 20 px). Unlit dots stay faint.
import QtQuick
import qs.core
import "kinds.js" as K

Canvas {
  id: c
  property string kind: "other"
  property real dot: 2
  property real gap: 1
  property color color: Theme.text
  property real faint: 0.12
  width: Math.round(7 * dot + 6 * gap); height: width
  onKindChanged: requestPaint()
  onColorChanged: requestPaint()
  onDotChanged: requestPaint()
  Component.onCompleted: requestPaint()
  onPaint: {
    const ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
    const g = K.glyphs[kind] || K.glyphs.other;
    for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++) {
      ctx.globalAlpha = g[y][x] === "#" ? 1 : faint;
      ctx.fillStyle = color;
      ctx.beginPath(); ctx.arc(x * (dot + gap) + dot / 2, y * (dot + gap) + dot / 2, dot / 2, 0, Math.PI * 2); ctx.fill();
    }
  }
}
