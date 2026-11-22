// Annotation stage of the area screenshot ("Draw" mode): satty-like tools drawn straight on the frozen frame.
// This item only draws and renders; the tool tiles live in ScreenshotArea's drop and set tool / color / size / fill here.
// Tools: brush line arrow rect ellipse text num (numbered marker) mark (highlighter) pixel (pixelate).
// Layers: frozen frame -> pixelated patches -> Canvas (everything else) -> text input. render() grabs the stage to a PNG.
import QtQuick
import qs.core

Item {
  id: ed
  property url frame
  property rect sel: Qt.rect(0, 0, 0, 0)   // selection in window px; the stage sits exactly on it. It can be resized: annotations are kept in WINDOW px, not stage px
  property real k: 1                       // frame pixels per window px
  property real winW: 1
  property real winH: 1
  property string tool: "arrow"
  property color color: "#ea6962"
  property int size: 6                     // stroke width in px (1..40); text pixel size follows it
  property bool fill: false
  readonly property int textPx: Math.round(10 + size * 2.4)
  signal wheelSize(int d)

  x: sel.x; y: sel.y; width: sel.width; height: sel.height
  clip: true

  property var ops: []
  property var undone: []
  property var cur: null
  property bool typing: false
  property real tx: 0
  property real ty: 0
  readonly property bool canUndo: ops.length > 0
  readonly property bool canRedo: undone.length > 0
  readonly property var patches: ops.filter(o => o.t === "pixel")

  function lumDark(c) { return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.6 }
  function clampX(v) { return Math.max(0, Math.min(width, v)) }
  function clampY(v) { return Math.max(0, Math.min(height, v)) }
  function nextNum() { return ops.filter(o => o.t === "num").length + 1 }
  function reset() { ops = []; undone = []; cur = null; typing = false }
  function undo() { if (!ops.length) return; undone.push(ops.pop()); opsChanged(); undoneChanged() }   // canUndo / canRedo bind to the lengths
  function redo() { if (!undone.length) return; ops.push(undone.pop()); opsChanged(); undoneChanged() }
  function commit(o) { ops.push(o); undone = []; opsChanged() }

  function begin(x, y) {
    x = clampX(x) + sel.x; y = clampY(y) + sel.y   // stage px -> window px
    const base = { t: tool, c: String(color), w: size, f: fill, dark: lumDark(color) }
    if (tool === "text") { tx = x; ty = y; typing = true; ti.text = ""; ti.forceActiveFocus(); return }
    if (tool === "num") { commit(Object.assign(base, { x: x, y: y, n: nextNum() })); return }
    if (tool === "brush" || tool === "mark") cur = Object.assign(base, { p: [{ x: x, y: y }] })
    else cur = Object.assign(base, { x0: x, y0: y, x1: x, y1: y })
  }
  function move(x, y) {
    if (!cur) return
    x = clampX(x) + sel.x; y = clampY(y) + sel.y
    if (cur.p) cur.p.push({ x: x, y: y }); else { cur.x1 = x; cur.y1 = y }
    curChanged()
  }
  function end() {
    if (!cur) return
    const o = cur; cur = null
    const tiny = o.p ? o.p.length < 2 : Math.abs(o.x1 - o.x0) + Math.abs(o.y1 - o.y0) < 4
    if (!tiny) commit(o)
  }
  function commitText() {
    if (!typing) return
    typing = false
    if (ti.text.trim() !== "") commit({ t: "text", x: tx, y: ty, s: ti.text, c: String(color), px: textPx, dark: lumDark(color) })
  }

  // grab the stage (frame crop + annotations) into a PNG at the frame's own resolution; done(ok) when written
  function render(path, done) {
    if (typing) commitText()
    const ok = ed.grabToImage(r => done(r.saveToFile(path)), Qt.size(Math.max(1, Math.round(width * k)), Math.max(1, Math.round(height * k))))
    if (!ok) done(false)
  }

  function draw(ctx, o) {
    ctx.save()
    ctx.strokeStyle = o.c; ctx.fillStyle = o.c; ctx.lineWidth = o.w; ctx.lineCap = "round"; ctx.lineJoin = "round"
    if (o.t === "brush" || o.t === "mark") {
      if (o.t === "mark") { ctx.globalAlpha = 0.38; ctx.lineWidth = o.w * 3.5; ctx.lineCap = "butt" }
      ctx.beginPath(); ctx.moveTo(o.p[0].x, o.p[0].y)
      for (let i = 1; i < o.p.length; i++) ctx.lineTo(o.p[i].x, o.p[i].y)
      ctx.stroke()
    } else if (o.t === "line" || o.t === "arrow") {
      ctx.beginPath(); ctx.moveTo(o.x0, o.y0); ctx.lineTo(o.x1, o.y1); ctx.stroke()
      if (o.t === "arrow") {
        const a = Math.atan2(o.y1 - o.y0, o.x1 - o.x0), L = 10 + o.w * 2.4
        ctx.beginPath(); ctx.moveTo(o.x1, o.y1)
        ctx.lineTo(o.x1 - L * Math.cos(a - 0.45), o.y1 - L * Math.sin(a - 0.45))
        ctx.lineTo(o.x1 - L * Math.cos(a + 0.45), o.y1 - L * Math.sin(a + 0.45))
        ctx.closePath(); ctx.fill()
      }
    } else if (o.t === "rect" || o.t === "ellipse") {
      const x = Math.min(o.x0, o.x1), y = Math.min(o.y0, o.y1), w = Math.abs(o.x1 - o.x0), h = Math.abs(o.y1 - o.y0)
      ctx.beginPath()
      if (o.t === "rect") ctx.rect(x, y, w, h); else ctx.ellipse(x, y, w, h)
      if (o.f) ctx.fill(); else ctx.stroke()
    } else if (o.t === "num") {
      const r = 10 + o.w * 2.5
      ctx.beginPath(); ctx.arc(o.x, o.y, r, 0, 2 * Math.PI); ctx.fill()
      ctx.fillStyle = o.dark ? "#1b1b1b" : "#ffffff"; ctx.font = "bold " + Math.round(r * 1.15) + "px " + Theme.font
      ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(String(o.n), o.x, o.y + 1)
    } else if (o.t === "text") {
      ctx.font = "bold " + o.px + "px " + Theme.font; ctx.textBaseline = "top"; ctx.fillText(o.s, o.x, o.y)
    }
    ctx.restore()
  }

  Image { id: bg; source: ed.frame; cache: false; x: -ed.sel.x; y: -ed.sel.y; width: ed.winW; height: ed.winH }

  Repeater {   // pixelate patches: the frame region re-sampled at 1/10 without smoothing = mosaic
    model: ed.patches
    ShaderEffectSource {
      required property var modelData
      x: Math.min(modelData.x0, modelData.x1) - ed.sel.x; y: Math.min(modelData.y0, modelData.y1) - ed.sel.y
      width: Math.abs(modelData.x1 - modelData.x0); height: Math.abs(modelData.y1 - modelData.y0)
      sourceItem: bg; sourceRect: Qt.rect(x + ed.sel.x, y + ed.sel.y, width, height)
      textureSize: Qt.size(Math.max(1, Math.round(width / 10)), Math.max(1, Math.round(height / 10))); smooth: false
    }
  }
  ShaderEffectSource {   // the patch being dragged
    visible: !!ed.cur && ed.cur.t === "pixel"
    x: ed.cur ? Math.min(ed.cur.x0, ed.cur.x1) - ed.sel.x : 0; y: ed.cur ? Math.min(ed.cur.y0, ed.cur.y1) - ed.sel.y : 0
    width: ed.cur ? Math.abs(ed.cur.x1 - ed.cur.x0) : 0; height: ed.cur ? Math.abs(ed.cur.y1 - ed.cur.y0) : 0
    sourceItem: bg; sourceRect: Qt.rect(x + ed.sel.x, y + ed.sel.y, width, height)
    textureSize: Qt.size(Math.max(1, Math.round(width / 10)), Math.max(1, Math.round(height / 10))); smooth: false
  }

  Canvas {
    id: cv
    anchors.fill: parent
    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.translate(-ed.sel.x, -ed.sel.y)   // ops are in window px
      for (const o of ed.ops) if (o.t !== "pixel") ed.draw(ctx, o)
      if (ed.cur && ed.cur.t !== "pixel") ed.draw(ctx, ed.cur)
    }
    Connections { target: ed; function onOpsChanged() { cv.requestPaint() } function onCurChanged() { cv.requestPaint() } function onSelChanged() { cv.requestPaint() } }
  }

  // a pixelate rectangle being dragged shows its outline only through the patch; nothing else to draw
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.CrossCursor
    acceptedButtons: Qt.LeftButton
    onPressed: m => { if (ed.typing) ed.commitText(); ed.begin(m.x, m.y) }   // a click elsewhere commits the text being typed
    onPositionChanged: m => { if (pressed) ed.move(m.x, m.y) }
    onReleased: ed.end()
    onWheel: w => ed.wheelSize(w.angleDelta.y > 0 ? 1 : -1)
  }

  TextInput {
    id: ti
    visible: ed.typing
    x: ed.tx - ed.sel.x; y: ed.ty - ed.sel.y
    color: ed.color; font.bold: true; font.family: Theme.font; font.pixelSize: ed.textPx
    selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
    onAccepted: ed.commitText()
    Keys.onEscapePressed: ev => { ed.typing = false; ev.accepted = true }
    onActiveFocusChanged: if (!activeFocus && ed.typing) ed.commitText()
  }
}
