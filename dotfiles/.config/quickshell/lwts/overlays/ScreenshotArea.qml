// Screenshots (Mod+Shift+S): the screen freezes, a Droplet of tiles grows out of the bar. Modes: Area (drag, saved on release), Draw (drag, then
// annotate: ShotEditor.qml), GIF (drag, wf-recorder until the hotkey / the pill), Window (hover lights a window, click captures it; the drop lists
// every window, a row captures it through niri), Screen (the whole output). Keys A D G W S pick a mode, Tab / Shift+Tab cycle them (in Draw: the tools), in Window / Screen ↑ ↓ choose a row and Enter captures it; Esc / right click / the hotkey again cancels.
// Window positions: niri gives none for tiled windows, so scripts/shot-rects.py finds them on the frozen frame (border colours + layout arithmetic).
// Capture goes to ~/Pictures/Screenshots + the clipboard; the toast has Edit / Folder / Copy / Delete.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.core
import qs.services
import qs.widgets

Scope {
  id: root
  property bool active: false
  property string rectsNote: ""        // why window outlines are unavailable (stderr of shot-rects.py), "" = fine
  property var rectData: ({})          // output -> windows found on its frozen frame (scripts/shot-rects.py), logical px
  property string screenHover: ""      // Screen mode: output lit from the drop's list ("*" = all)
  property string hoverOut: ""         // Screen mode: output under the pointer
  readonly property var screensSorted: Quickshell.screens.slice().sort((a, b) => a.x - b.x || a.y - b.y)
  function captureScreens(names) {     // one output: crop its frame whole; several: composed on one canvas by their layout positions
    const ss = screensSorted.filter(sc => names.includes(sc.name))
    if (!ss.length) return
    const t = root.ts, dir = root.freezeDir
    if (ss.length === 1) {
      Quickshell.execDetached(["sh", "-c", root.script, "sh", "iw:ih:0:0", frameOf(ss[0].name), dir, t, ss[0].name + " " + ss[0].width + "×" + ss[0].height])
    } else {
      const x0 = Math.min(...ss.map(sc => sc.x)), y0 = Math.min(...ss.map(sc => sc.y))
      const W = Math.max(...ss.map(sc => sc.x + sc.width)) - x0, H = Math.max(...ss.map(sc => sc.y + sc.height)) - y0
      let args = ["-f", "lavfi", "-i", "color=c=black:s=" + W + "x" + H], fc = "", last = "[0:v]"
      ss.forEach((sc, i) => {
        args = args.concat(["-i", frameOf(sc.name)])
        fc += "[" + (i + 1) + ":v]scale=" + sc.width + ":" + sc.height + "[s" + i + "];" + last + "[s" + i + "]overlay=" + (sc.x - x0) + ":" + (sc.y - y0) + ":format=rgb[o" + i + "];"
        last = "[o" + i + "]"
      })
      args = args.concat(["-filter_complex", fc.slice(0, -1), "-map", last, "-frames:v", "1"])
      Quickshell.execDetached(["sh", "-c", root.bothScript, "sh", dir, t, "All screens " + W + "×" + H].concat(args))
    }
    root.active = false; root.ts = ""
  }
  property int listHover: -1           // window id hovered in the drop's list: its rectangle is lit on the picture
  function windowAt(out, x, y) {       // the smallest tile under the pointer
    let best = null
    for (const w of (rectData[out] || [])) if (x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h && (!best || w.w * w.h < best.w * best.h)) best = w
    return best
  }
  function rectOf(out, id) { return (rectData[out] || []).find(w => w.id === id) || null }
  Process {
    id: rects
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") { root.rectsNote = text.trim(); console.warn("shot-rects: " + text.trim()) } }
    stdout: StdioCollector { onStreamFinished: { try { if (root.ts !== "") root.rectData = JSON.parse(text) } catch (e) { root.rectData = ({}) } } }
  }
  property int kbSel: -1               // keyboard-chosen row of the drop's list (Window / Screen)
  readonly property var modeOrder: ["shot", "draw", "gif", "window", "screen"]
  function setMode(m) { mode = m; kbSel = -1; listHover = -1; screenHover = "" }
  function cycleMode(d) { setMode(modeOrder[(modeOrder.indexOf(mode) + d + modeOrder.length) % modeOrder.length]) }
  property bool editBusy: false       // a window is in Draw mode: the other outputs' drops step aside
  property string edTool: "arrow"      // Draw: remembered between captures
  property color edColor: Theme.red
  property int edSize: 6               // stroke px (text size follows)
  property bool edFill: false
  // Every output is frozen first: one grim per output writes shot-<ts>-<output>.png, each overlay shows its own frame, and the area is
  // cropped out of that frame (nothing that moves on screen can change under the selection). The hotkey again / Esc / right click cancels.
  property string ts: ""
  readonly property string freezeDir: (Quickshell.env("XDG_RUNTIME_DIR") || (Quickshell.env("HOME") + "/.cache")) + "/lwts-shot"   // tmpfs: frames are big and short-lived
  function frameOf(name) { return ts === "" ? "" : freezeDir + "/shot-" + ts + "-" + name + ".png" }
  function start() {
    if (active || grab.running) { cancel(); return }
    ts = String(Date.now())
    screenHover = ""; hoverOut = ""; listHover = -1; rectData = ({}); rectsNote = ""
    grab.command = ["sh", "-c", 'd=$1; t=$2; shift 2; mkdir -p "$d"; rm -f "$d"/shot-*.png "$d"/edit-*.png; trap \'kill $(jobs -p) 2>/dev/null; exit 1\' TERM INT; for o in "$@"; do grim -l 0 -o "$o" "$d/shot-$t-$o.png" & done; fail=0; for j in $(jobs -p); do wait $j || fail=1; done; [ $fail = 0 ] || notify-send -a Screenshot "Screenshot failed" "grim could not capture an output"; exit $fail', "sh", freezeDir, ts].concat(Quickshell.screens.map(s => s.name))
    grab.running = true
  }
  function dropFrozen() { if (ts !== "") Quickshell.execDetached(["sh", "-c", 'sleep 0.4; rm -f "$1"/shot-"$2"-*.png', "sh", freezeDir, ts]); ts = "" }
  function cancel() { recStart.stop(); active = false; editBusy = false; grab.running = false; rects.running = false; rectData = ({}); rectsNote = ""; listHover = -1; screenHover = ""; hoverOut = ""; dropFrozen() }
  Process {
    id: grab
    onExited: code => {
      if (root.ts === "") return
      if (code !== 0) { root.dropFrozen(); return }
      root.active = true
      rects.command = ["python3", "-I", Quickshell.shellPath("scripts/shot-rects.py")].concat(Quickshell.screens.map(s => s.name + "=" + root.frameOf(s.name)))
      root.rectsNote = ""; rects.running = true
    }
  }   // ts "" = cancelled meanwhile
  property bool autoClick: false
  function window(auto) { autoClick = !!auto; active = false; grab.running = false; dropFrozen(); pick.restart() }
  // GIF: the same frozen selection, then wf-recorder records that region until the hotkey (or the pill) is pressed again;
  // ffmpeg makes the GIF (palette) and the same action toast appears.
  property string mode: "shot"        // "shot" | "gif": what the selection does
  property string recOut: ""
  property rect recRect: Qt.rect(0, 0, 0, 0)   // logical, relative to the recorded output
  property string recGeom: ""
  property string recLabel: ""
  property double recSince: 0
  property double nowMs: 0
  function stopRec() { rec.signal(2) }   // SIGINT: wf-recorder finalizes the file, onExited converts it
  Timer { id: recStart; interval: 260; onTriggered: { root.recSince = Date.now(); root.nowMs = root.recSince; rec.running = true } }   // the overlay is gone first
  Timer { interval: 500; repeat: true; running: rec.running; onTriggered: root.nowMs = Date.now() }
  Process {
    id: rec
    property string file: ""
    command: ["wf-recorder", "-D", "-r", "15", "-o", root.recOut, "-g", root.recGeom, "-f", rec.file]
    onExited: Quickshell.execDetached(["sh", "-c", root.gifScript, "sh", rec.file, root.recLabel])
  }
  IpcHandler {
    target: "shot"
    function area(): void { if (rec.running) root.stopRec(); else if (recStart.running) recStart.stop(); else { root.mode = "shot"; root.start() } }
    function gif(): void { if (rec.running) root.stopRec(); else if (recStart.running) recStart.stop(); else { root.mode = "gif"; root.start() } }
    function window(): void { root.window() }
  }

  readonly property string save: 'd="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/$(date +%Y-%m-%d_%H-%M-%S).png"; '
  // $1 = crop "w:h:x:y" in pixels of the frozen frame, $2 = this output's frame, $3/$4 = dir and timestamp (all frames removed here)
  readonly property string script: 'LBL="$5"; ' + save + 'ffmpeg -y -v error -i "$2" -vf "crop=$1" "$f"; r=$?; rm -f "$3"/shot-"$4"-*.png; [ $r = 0 ] && [ -s "$f" ] || { rm -f "$f"; notify-send -a Screenshot "Screenshot failed" "ffmpeg exit $r"; exit 1; }; wl-copy --type image/png < "$f"; ' + tail
  // window: niri picks (Esc there = null id = nothing), copies the window to the clipboard; we write the file from it
  // $1 = "auto": click for the user (the cursor has not moved since his click); only if ydotoold is up, else he clicks
  readonly property string windowScript: 't=$(mktemp); niri msg -j pick-window > "$t" & p=$!; '
    + 'if [ "$1" = auto ] && [ -S "${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}" ]; then sleep 0.15; ydotool click 0xC0 >/dev/null 2>&1; fi; '
    + 'wait $p; id=$(jq -r ".id // empty" < "$t"); rm -f "$t"; [ -n "$id" ] || exit 0; ' + save
    + 'niri msg action screenshot-window --id "$id" --write-to-disk false || exit 1; sleep 0.3; '
    + 'wl-paste --type image/png > "$f" && [ -s "$f" ] || { rm -f "$f"; exit 1; }; ' + tail
  // after a capture: a LWTS toast with a preview and actions (the card renders every -A as a button); the file is already saved + copied
  // $1 = the recorded mp4 (removed after the conversion)
  readonly property string gifScript: 'm="$1"; [ -s "$m" ] || { rm -f "$m"; notify-send -a Screenshot "Recording failed" "wf-recorder produced no file"; exit 1; }; d="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/$(date +%Y-%m-%d_%H-%M-%S).gif"; '
    + 'ffmpeg -y -v error -i "$m" -vf "fps=15,scale=\'min(iw,960)\':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$f"; r=$?; [ $r = 0 ] && rm -f "$m"; '
    + '[ $r = 0 ] && [ -s "$f" ] || { rm -f "$f"; notify-send -a Screenshot "GIF failed" "ffmpeg could not convert; the recording is kept: $m"; exit 1; }; '
    + 'a=$(notify-send -a Screenshot -i "$f" -A open=Open -A folder=Folder -A copy=Copy -A delete=Delete "GIF saved" "${2:+$2 · }$(basename "$f")"); '
    + 'case "$a" in open) xdg-open "$f";; folder) xdg-open "$(dirname "$f")";; copy) wl-copy --type image/gif < "$f";; delete) rm -f -- "$f";; esac'
  // a window picked from the drop's list: niri renders it itself (whole window, even off screen or on another workspace)
  // several outputs on one canvas: $1 dir, $2 ts, $3 label, then the ffmpeg input/filter args (output file is added here)
  readonly property string bothScript: 'z="$1"; t="$2"; LBL="$3"; shift 3; ' + save + 'ffmpeg -y -v error "$@" "$f"; r=$?; rm -f "$z"/shot-"$t"-*.png; '
    + '[ $r = 0 ] && [ -s "$f" ] || { rm -f "$f"; notify-send -a Screenshot "Screenshot failed" "ffmpeg exit $r"; exit 1; }; wl-copy --type image/png < "$f"; ' + tail
  readonly property string windowIdScript: 'id="$1"; LBL="$2"; ' + save + 'niri msg action screenshot-window --id "$id" --path "$f" || { notify-send -a Screenshot "Screenshot failed" "niri could not capture window $id"; exit 1; }; '
    + 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$f" ] && break; sleep 0.1; done; '
    + '[ -s "$f" ] || { rm -f "$f"; notify-send -a Screenshot "Screenshot failed" "niri wrote no file for window $id"; exit 1; }; ' + tail
  readonly property string postScript: 'f="$1"; LBL="$2"; wl-copy --type image/png < "$f"; ' + tail   // Draw: the rendered file is already saved
  readonly property string tail: 'a=$(notify-send -a Screenshot -i "$f" -A edit=Edit -A folder=Folder -A copy=Copy -A delete=Delete "Screenshot saved" "${LBL:+$LBL · }$(basename "$f")"); '
    + 'case "$a" in '
    + 'edit) if command -v satty >/dev/null; then satty -f "$f"; elif command -v swappy >/dev/null; then swappy -f "$f"; else xdg-open "$f"; fi;; '
    + 'folder) xdg-open "$(dirname "$f")";; '
    + 'copy) wl-copy --type image/png < "$f";; '
    + 'delete) rm -f -- "$f";; esac'
  Timer { id: pick; interval: 220; onTriggered: Quickshell.execDetached(["sh", "-c", root.windowScript, "sh", root.autoClick ? "auto" : ""]) }   // overlay gone first

  Variants {
    model: root.active ? Quickshell.screens : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-shot"
      WlrLayershell.keyboardFocus: win.editing || (!root.editBusy && win.modelData.name === Compositor.focusedOutput) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None   // Esc works on the focused output; right click / the hotkey cancel anywhere
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"

      property point a: Qt.point(0, 0)
      property point b: Qt.point(0, 0)
      property bool dragging: false
      property point cur: Qt.point(0, 0)   // the pointer: crosshair + magnifier follow it
      property bool hasCur: false
      property bool editing: false
      readonly property var hoverWin: root.mode === "window" && win.hasCur ? root.windowAt(win.modelData.name, win.cur.x, win.cur.y) : null   // the window under the pointer (Window mode)
      readonly property bool lit: root.mode === "screen" && !win.editing && (root.screenHover !== "" ? (root.screenHover === "*" || root.screenHover === modelData.name) : mouseArea.containsMouse)
      readonly property var target: root.mode !== "window" ? null : root.listHover >= 0 ? root.rectOf(modelData.name, root.listHover) : hoverWin
      function captureTarget() {    // click in Window mode: that window as it is on the frozen frame
        const t = win.target; if (!t || frameImg.status !== Image.Ready) return
        const x0 = Math.max(0, t.cx), y0 = Math.max(0, t.cy), x1 = Math.min(win.width, t.cx + t.cw), y1 = Math.min(win.height, t.cy + t.ch)
        if (x1 - x0 < 4 || y1 - y0 < 4) return
        const k = frameImg.implicitWidth > 0 && win.width > 0 ? frameImg.implicitWidth / win.width : 1
        const fz = root.frameOf(win.modelData.name), ts = root.ts; root.active = false; root.ts = ""
        Quickshell.execDetached(["sh", "-c", root.script, "sh", Math.round((x1 - x0) * k) + ":" + Math.round((y1 - y0) * k) + ":" + Math.round(x0 * k) + ":" + Math.round(y0 * k), fz, root.freezeDir, ts, t.title || t.app_id])
      }
      property string hint: ""   // what the hovered tile does (a small label under the drop)
      function finishEdit(copyOnly) {   // render the stage to a PNG: saved + toast, or copy only
        const path = copyOnly ? root.freezeDir + "/edit-" + root.ts + ".png"
                              : Quickshell.env("HOME") + "/Pictures/Screenshots/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png"
        Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/Pictures/Screenshots"])
        ed.render(path, ok => {
          if (!ok) { Quickshell.execDetached(["notify-send", "-a", "Screenshot", "Could not save the drawing", path]); return }   // the editor stays open
          if (ok) Quickshell.execDetached(["sh", "-c", copyOnly ? 'wl-copy --type image/png < "$1"; rm -f "$1"' : root.postScript, "sh", path, "Drawn " + Math.round(ed.width) + "×" + Math.round(ed.height)])
          root.cancel()
        })
      }
      readonly property int zoom: 8
      function moveSel(d) {   // arrows in Window / Screen mode walk the drop's list; the chosen target lights on the picture
        const n = root.mode === "screen" ? tools.screenRows.length : Math.min(tools.winList.length, 8)
        if (n <= 0) return
        root.kbSel = root.kbSel < 0 ? (d > 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, root.kbSel + d))
        if (root.mode === "screen") root.screenHover = tools.screenRows[root.kbSel].id
        else root.listHover = tools.winList[root.kbSel].id
      }
      function confirm() {   // Enter: capture what is lit (chosen row, hovered row, or the target under the pointer)
        if (root.mode === "screen") {
          if (root.screenHover !== "") root.captureScreens(root.screenHover === "*" ? root.screensSorted.map(sc => sc.name) : [root.screenHover])
          else if (win.lit) root.captureScreens([win.modelData.name])
        } else if (root.mode === "window") {
          if (root.listHover >= 0) {
            const w = Compositor.windows[root.listHover]
            Quickshell.execDetached(["sh", "-c", root.windowIdScript, "sh", String(root.listHover), w ? (w.title || w.app_id) : ""]); root.cancel()
          } else if (win.target) win.captureTarget()
        }
      }
      function tool(id) {
        if (id === "shot" || id === "gif" || id === "draw" || id === "window" || id === "screen") root.setMode(id)
        else root.cancel()
      }
      readonly property int lensSize: 140
      readonly property rect sel: Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(a.x - b.x), Math.abs(a.y - b.y))
      readonly property color dim: Qt.rgba(0, 0, 0, 0.4)

      Image { id: frameImg; anchors.fill: parent; source: root.ts !== "" ? "file://" + root.frameOf(win.modelData.name) : ""; cache: false; fillMode: Image.Stretch }   // the frozen screen
      Rectangle { visible: !win.dragging && !win.editing && !win.target && !win.lit; anchors.fill: parent; color: win.dim }   // before the drag: the whole screen is dimmed
      Item {   // around the rectangle: dim; inside: the real screen
        visible: win.dragging || win.editing; anchors.fill: parent
        Rectangle { color: win.dim; x: 0; y: 0; width: parent.width; height: win.sel.y }
        Rectangle { color: win.dim; x: 0; y: win.sel.y + win.sel.height; width: parent.width; height: parent.height - y }
        Rectangle { color: win.dim; x: 0; y: win.sel.y; width: win.sel.x; height: win.sel.height }
        Rectangle { color: win.dim; x: win.sel.x + win.sel.width; y: win.sel.y; width: parent.width - x; height: win.sel.height }
        Rectangle { x: win.sel.x - 1; y: win.sel.y - 1; width: win.sel.width + 2; height: win.sel.height + 2; color: "transparent"; border.width: 1; border.color: Theme.accent }
        Rectangle {
          x: Math.min(win.sel.x, parent.width - width); y: win.sel.y > height + 6 ? win.sel.y - height - 4 : win.sel.y + win.sel.height + 4
          width: sizeText.implicitWidth + 12; height: sizeText.implicitHeight + 6; radius: Theme.radiusInner
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
          Text { id: sizeText; anchors.centerIn: parent; text: (root.mode === "gif" ? "GIF · " : "") + Math.round(win.sel.width) + " × " + Math.round(win.sel.height)
                 color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
        }
      }

      Item {   // the bar stays as it was (frozen, not dimmed) so the tool drop flows out of it
        clip: true; width: parent.width; height: Prefs.barHeight
        y: Prefs.barPosition === "bottom" ? win.height - height : 0
        Image { source: frameImg.source; cache: false; y: -parent.y; width: win.width; height: win.height }
      }

      Item {   // Screen mode: the output that will be captured is framed (the others stay dimmed) with what it is
        visible: win.lit; anchors.fill: parent
        Rectangle { anchors.fill: parent; color: Theme.tint; border.width: 3; border.color: Theme.accent }
        Rectangle {
          anchors.centerIn: parent
          width: litText.implicitWidth + 28; height: litText.implicitHeight + 16; radius: Theme.radiusInner
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92); border.width: 1; border.color: Theme.line
          Text {
            id: litText; anchors.centerIn: parent; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(14 * Theme.scale)
            text: root.screenHover === "*" ? "All screens · " + (Math.max(...root.screensSorted.map(sc => sc.x + sc.width)) - Math.min(...root.screensSorted.map(sc => sc.x))) + "×" + (Math.max(...root.screensSorted.map(sc => sc.y + sc.height)) - Math.min(...root.screensSorted.map(sc => sc.y)))
                  : "Screen " + (root.screensSorted.findIndex(sc => sc.name === win.modelData.name) + 1) + " · " + win.modelData.name + " · " + win.modelData.width + "×" + win.modelData.height
          }
        }
      }

      Item {   // Window mode: the window under the pointer (or hovered in the list) is cut out of the dim and framed
        id: winLight
        visible: !!win.target && !win.editing; anchors.fill: parent
        readonly property var t: win.target || ({ x: 0, y: 0, w: 0, h: 0, title: "", app_id: "" })
        readonly property real x0: Math.max(0, t.x)
        readonly property real y0: Math.max(0, t.y)
        readonly property real x1: Math.min(width, t.x + t.w)
        readonly property real y1: Math.min(height, t.y + t.h)
        Rectangle { color: win.dim; x: 0; y: 0; width: parent.width; height: winLight.y0 }
        Rectangle { color: win.dim; x: 0; y: winLight.y1; width: parent.width; height: parent.height - y }
        Rectangle { color: win.dim; x: 0; y: winLight.y0; width: winLight.x0; height: winLight.y1 - winLight.y0 }
        Rectangle { color: win.dim; x: winLight.x1; y: winLight.y0; width: parent.width - x; height: winLight.y1 - winLight.y0 }
        Rectangle { x: winLight.x0; y: winLight.y0; width: winLight.x1 - winLight.x0; height: winLight.y1 - winLight.y0; radius: Theme.radiusInner
                    color: Theme.tint; border.width: 2; border.color: Theme.accent }
        Rectangle {
          x: winLight.x0 + 10; y: winLight.y0 + 10
          width: Math.min(winLight.x1 - winLight.x0 - 20, lightText.implicitWidth + 14); height: lightText.implicitHeight + 8; radius: Theme.radiusInner
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92); border.width: 1; border.color: Theme.line
          Text { id: lightText; anchors.centerIn: parent; width: parent.width - 14; elide: Text.ElideRight; text: winLight.t.title || winLight.t.app_id
                 color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
        }
      }

      Item {   // crosshair across the output + a pixel magnifier next to the pointer (the frame is frozen, so it is exact)
        visible: win.hasCur && !win.editing && root.mode !== "window" && root.mode !== "screen"; anchors.fill: parent
        Rectangle { x: 0; y: win.cur.y; width: parent.width; height: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) }
        Rectangle { x: win.cur.x; y: 0; width: 1; height: parent.height; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) }
        Rectangle {
          id: lens
          width: win.lensSize; height: win.lensSize; clip: true; color: "black"; border.width: 1; border.color: Theme.accent
          x: win.cur.x + 24 + width > win.width - 8 ? win.cur.x - 24 - width : win.cur.x + 24
          y: win.cur.y + 24 + height + 22 > win.height - 8 ? win.cur.y - 24 - height - 22 : win.cur.y + 24
          Image {
            source: frameImg.source; cache: false; smooth: false; mipmap: false
            width: win.width * win.zoom; height: win.height * win.zoom
            x: lens.width / 2 - (win.cur.x + 0.5) * win.zoom; y: lens.height / 2 - (win.cur.y + 0.5) * win.zoom
          }
          Rectangle { anchors.centerIn: parent; width: win.zoom + 2; height: win.zoom + 2; color: "transparent"; border.width: 1; border.color: Theme.accent }   // the pixel under the pointer
        }
        Rectangle {
          x: lens.x; y: lens.y + lens.height + 4; width: coord.implicitWidth + 12; height: coord.implicitHeight + 6; radius: Theme.radiusInner
          color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
          Text { id: coord; anchors.centerIn: parent; text: Math.round(win.cur.x) + ", " + Math.round(win.cur.y)
                 color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
        }
      }


      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onExited: { win.hasCur = false; if (root.hoverOut === win.modelData.name) root.hoverOut = "" }
        onEntered: root.hoverOut = win.modelData.name
        cursorShape: root.mode === "window" ? (win.target ? Qt.PointingHandCursor : Qt.ArrowCursor) : root.mode === "screen" ? Qt.PointingHandCursor : Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: m => { if (m.button === Qt.RightButton) { root.cancel(); return } if (win.editing) return; if (root.mode === "window") { win.captureTarget(); return } if (root.mode === "screen") { root.captureScreens([win.modelData.name]); return } win.a = Qt.point(m.x, m.y); win.b = win.a; win.dragging = true }
        onPositionChanged: m => { win.cur = Qt.point(m.x, m.y); win.hasCur = true; if (win.dragging) win.b = Qt.point(Math.max(0, Math.min(width, m.x)), Math.max(0, Math.min(height, m.y))) }
        onReleased: m => {
          if (!win.dragging) return;
          win.dragging = false;
          if (root.mode === "draw") {
            if (win.sel.width < 8 || win.sel.height < 8) { root.cancel(); return }
            ed.reset(); win.editing = true; root.editBusy = true; return
          }
          if (root.mode === "gif") {
            if (win.sel.width < 8 || win.sel.height < 8) { root.cancel(); return }
            const e2 = n => n % 2 === 0 ? n : n - 1;   // x264 wants even sizes
            root.recOut = win.modelData.name; root.recRect = win.sel; root.recLabel = "GIF " + Math.round(win.sel.width) + "×" + Math.round(win.sel.height)
            root.recGeom = Math.round(win.screen.x + win.sel.x) + "," + Math.round(win.screen.y + win.sel.y) + " " + e2(Math.max(2, Math.round(win.sel.width))) + "x" + e2(Math.max(2, Math.round(win.sel.height)))
            rec.file = Quickshell.env("HOME") + "/.cache/lwts/rec-" + root.ts + ".mp4"
            Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.cache/lwts"]); root.active = false; root.dropFrozen(); recStart.restart(); return
          }
          if (win.sel.width < 4 || win.sel.height < 4) { root.window(true); return }   // a plain click: that window
          const k = frameImg.implicitWidth > 0 && win.width > 0 ? frameImg.implicitWidth / win.width : 1;   // frame pixels per logical pixel
          const w = Math.max(1, Math.round(win.sel.width * k)), h = Math.max(1, Math.round(win.sel.height * k));
          const x = Math.min(Math.round(win.sel.x * k), Math.max(0, frameImg.implicitWidth - w)), y = Math.min(Math.round(win.sel.y * k), Math.max(0, frameImg.implicitHeight - h));
          const fz = root.frameOf(win.modelData.name), t = root.ts; root.active = false; root.ts = "";
          Quickshell.execDetached(["sh", "-c", root.script, "sh", w + ":" + h + ":" + x + ":" + y, fz, root.freezeDir, t, "Area " + Math.round(win.sel.width) + "×" + Math.round(win.sel.height)]);
        }
      }
      Item {   // glass: niri draws no blur on the Overlay layer, so the frozen frame is blurred behind the drop (same switch as the bar)
        id: glass
        visible: Prefs.blurOn && tools.opened
        x: tools.x + tools.fl; y: tools.y; width: tools.w; height: tools.h
        layer.enabled: visible
        layer.effect: MultiEffect { maskEnabled: true; maskSource: glassMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        Item { anchors.fill: parent; clip: true
          Image {
            source: frameImg.source; cache: false; x: -glass.x; y: -glass.y; width: win.width; height: win.height
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; autoPaddingEnabled: false }
          }
        }
      }
      Item {   // the drop's body shape (rounded away from the bar) as the glass mask
        id: glassMask
        visible: false; layer.enabled: true
        x: glass.x; y: glass.y; width: glass.width; height: glass.height
        Item { anchors.fill: parent; clip: true
          Rectangle { y: tools.flip ? 0 : -tools.r; width: parent.width; height: parent.height + tools.r; radius: tools.r; color: "white" }
        }
      }
      component Sep: Item { width: 9; height: tools.cell; Rectangle { anchors.centerIn: parent; width: 1; height: parent.height - 10; color: Theme.line } }
      component Cell: MouseArea {   // a tile-looking cell for colours and sizes (the same fill / tint rules as Tile)
        id: cellRoot
        property bool on: false
        default property alias face: faceBox.data
        width: tools.cell; height: tools.cell; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        Rectangle {
          anchors.fill: parent; radius: Theme.radiusInner
          color: cellRoot.on ? (cellRoot.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.26) : Theme.tint) : cellRoot.containsMouse ? Theme.fillHover : "transparent"; border.width: 1; border.color: Theme.edge
          Behavior on color { ColorAnimation { duration: Motion.duration } }
        }
        Item { id: faceBox; anchors.fill: parent }
      }

      ShotEditor {   // Draw mode: annotations on the selected area of the frozen frame
        id: ed
        visible: win.editing
        frame: frameImg.source; sel: win.sel; winW: win.width; winH: win.height
        k: frameImg.implicitWidth > 0 && win.width > 0 ? frameImg.implicitWidth / win.width : 1
        tool: root.edTool; color: root.edColor; size: root.edSize; fill: root.edFill
        onTypingChanged: if (!typing) keys.forceActiveFocus()
        onWheelSize: d => root.edSize = Math.max(1, Math.min(40, root.edSize + d))
      }

      Item {   // Draw: the selection is resized by its eight handles (annotations stay where they are on the picture)
        id: handles
        visible: win.editing; anchors.fill: parent
        Repeater {
          model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]
          MouseArea {
            id: h
            required property var modelData
            readonly property real sz: Math.round(14 * Theme.scale)
            property rect base: Qt.rect(0, 0, 0, 0)
            width: sz; height: sz
            x: win.sel.x + win.sel.width * modelData[0] - sz / 2
            y: win.sel.y + win.sel.height * modelData[1] - sz / 2
            hoverEnabled: true
            cursorShape: modelData[0] === 0.5 ? Qt.SizeVerCursor : modelData[1] === 0.5 ? Qt.SizeHorCursor : modelData[0] === modelData[1] ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            onPressed: h.base = win.sel
            onPositionChanged: m => {
              if (!pressed) return
              const p = mapToItem(handles, m.x, m.y)
              let l = base.x, t = base.y, r = base.x + base.width, b = base.y + base.height
              if (modelData[0] === 0) l = Math.min(p.x, r - 24); else if (modelData[0] === 1) r = Math.max(p.x, l + 24)
              if (modelData[1] === 0) t = Math.min(p.y, b - 24); else if (modelData[1] === 1) b = Math.max(p.y, t + 24)
              win.a = Qt.point(Math.max(0, l), Math.max(0, t)); win.b = Qt.point(Math.min(win.width, r), Math.min(win.height, b))
            }
            Rectangle {
              anchors.centerIn: parent; width: parent.sz - 4; height: width; radius: Theme.radiusInner
              color: h.containsMouse || h.pressed ? Qt.lighter(Theme.accent, 1.2) : Theme.accent; border.width: 1; border.color: Theme.surface
            }
          }
        }
      }

      Droplet {   // the tool panel grows out of the bar; compact Quick Settings tiles, icons only
        id: tools
        readonly property int cell: Math.round(30 * Theme.scale)
        readonly property int gap: 4
        readonly property bool listOn: (root.mode === "window" || root.mode === "screen") && !win.editing
        readonly property var screenRows: {   // left to right; the last row = all of them
          const ss = root.screensSorted
          const rows = ss.map((sc, i) => ({ id: sc.name, title: "Screen " + (i + 1), trail: sc.name + " · " + sc.width + "×" + sc.height }))
          if (ss.length > 1) rows.push({ id: "*", title: "All screens", trail: ss.length + " screens" })
          return rows
        }
        readonly property var winList: {   // windows of every workspace: the ones visible on this output first
          const here = root.rectData[win.modelData.name] || [], ids = new Set(here.map(w => w.id))
          return Compositor.windowList.slice().sort((a, b) => (ids.has(b.id) ? 1 : 0) - (ids.has(a.id) ? 1 : 0) || (b.is_focused ? 1 : 0) - (a.is_focused ? 1 : 0))
        }
        onWinListChanged: root.listHover = -1   // rows are rebuilt: a hovered row would never report leaving
        readonly property int rowH: Math.round(30 * Theme.scale)
        readonly property bool noOutlines: root.mode === "window" && root.rectsNote.indexOf("no border colours") >= 0
        readonly property int noteH: noOutlines ? Math.round(34 * Theme.scale) : 0
        readonly property int listH: !listOn ? 0 : root.mode === "screen" ? screenRows.length * rowH : Math.min(winList.length, 8) * rowH + noteH
        readonly property real wantW: win.editing ? 14 * cell + 15 * gap + 20 : listOn ? Math.max(5 * cell + 4 * gap + 20, Math.round(340 * Theme.scale)) : 5 * cell + 4 * gap + 20
        readonly property var toolList: [["brush", "paint-brush", "Brush · B"], ["line", "line-segment", "Line · L"], ["arrow", "arrow-up-right", "Arrow · A"], ["rect", "rectangle", "Rectangle · R"],
                                         ["ellipse", "circle", "Ellipse · E"], ["text", "text-t", "Text · T"], ["num", "number-circle-one", "Numbered marker · N"],
                                         ["mark", "highlighter", "Highlighter · H"], ["pixel", "grid-four", "Pixelate · P"]]
        flip: Prefs.barPosition === "bottom"
        fullWidth: wantW; contentWidth: wantW
        fullHeight: win.editing ? 2 * cell + gap + 20 : cell + 20 + (listH > 0 ? gap + listH : 0)
        Behavior on fullWidth { enabled: tools.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
        Behavior on fullHeight { enabled: tools.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
        y: Prefs.barPosition === "bottom" ? win.height - Prefs.barHeight - height : Prefs.barHeight
        Component.onCompleted: { if (!root.editBusy) open() }
        Connections { target: win; function onDraggingChanged() { if (win.dragging) tools.close(); else tools.open() } }
        Connections { target: root; function onEditBusyChanged() { if (root.editBusy && !win.editing) tools.close() } }
        MouseArea { anchors.fill: parent; hoverEnabled: true }   // the drop's empty parts never start a selection and take the hover: nothing under the drop is lit while the pointer is on it

        Row {   // modes (before a selection)
          visible: !win.editing
          x: Math.round((parent.width - width) / 2); y: 10; spacing: tools.gap
          Repeater {
            model: [{ id: "shot", icon: "selection", name: "Area · A", mode: true }, { id: "draw", icon: "pencil-simple-line", name: "Draw on it · D", mode: true },
                    { id: "gif", icon: "gif", name: "GIF · G", mode: true }, { id: "window", icon: "app-window", name: "Window · W", mode: true }, { id: "screen", icon: "monitor", name: "Whole screen · S", mode: true }]
            Tile {
              required property var modelData
              wide: false; icon: modelData.icon
              on: !!modelData.mode && root.mode === modelData.id
              width: tools.cell; height: tools.cell
              onAct: win.tool(modelData.id)
              onContainsMouseChanged: win.hint = containsMouse ? modelData.name : ""
            }
          }
        }

        Column {   // Screen mode: which output(s); hover lights them on the picture, click captures
          visible: tools.listOn && root.mode === "screen"
          x: 10; y: 10 + tools.cell + tools.gap; width: parent.width - 20
          Repeater {
            model: root.mode === "screen" ? tools.screenRows : []
            ListRow {
              required property var modelData
              required property int index
              width: parent.width; implicitHeight: tools.rowH
              icon: modelData.id === "*" ? "monitors" : "monitor"
              title: modelData.title; trail: modelData.trail
              on: root.hoverOut === modelData.id
              focused: root.kbSel === index
              onContainsMouseChanged: { if (containsMouse) root.kbSel = -1; root.screenHover = containsMouse ? modelData.id : (root.screenHover === modelData.id ? "" : root.screenHover) }
              onAct: root.captureScreens(modelData.id === "*" ? root.screensSorted.map(sc => sc.name) : [modelData.id])
            }
          }
        }

        Text {   // borders off: nothing to find windows by
          visible: tools.noOutlines && tools.listOn
          x: 14; y: 10 + tools.cell + tools.gap; width: parent.width - 28; height: tools.noteH; wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
          text: "Window outlines need window borders (they are off). Pick a window from the list."
          color: Theme.dim; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale)
        }

        ListView {   // Window mode: every window; hover lights it on the picture, click captures it (niri renders it whole)
          visible: tools.listOn && root.mode === "window"
          x: 10; y: 10 + tools.cell + tools.gap + tools.noteH; width: parent.width - 20; height: tools.listH - tools.noteH
          clip: true; interactive: contentHeight > height; boundsBehavior: Flickable.StopAtBounds
          model: tools.listOn ? tools.winList : []
          delegate: ListRow {
            required property var modelData
            required property int index
            width: ListView.view.width; implicitHeight: tools.rowH
            iconSource: modelData.app_id ? Quickshell.iconPath(modelData.app_id.toLowerCase(), true) : ""
            icon: "app-window"
            title: modelData.title || modelData.app_id
            trail: root.rectOf(win.modelData.name, modelData.id) ? "" : "other view"
            on: modelData.is_focused
            focused: root.kbSel === index
            onContainsMouseChanged: { if (containsMouse) root.kbSel = -1; root.listHover = containsMouse ? modelData.id : (root.listHover === modelData.id ? -1 : root.listHover) }
            onAct: { Quickshell.execDetached(["sh", "-c", root.windowIdScript, "sh", String(modelData.id), modelData.title || modelData.app_id]); root.cancel() }
          }
        }

        Column {   // Draw: tools, undo / redo, copy / save / close; below: colour, size, fill
          visible: win.editing
          anchors.centerIn: parent; spacing: tools.gap
          Row {
            spacing: tools.gap
            Repeater {
              model: tools.toolList
              Tile { required property var modelData; wide: false; icon: modelData[1]; on: root.edTool === modelData[0]; width: tools.cell; height: tools.cell
                     onAct: root.edTool = modelData[0]; onContainsMouseChanged: win.hint = containsMouse ? modelData[2] : "" }
            }
            Sep {}
            Tile { wide: false; icon: "arrow-counter-clockwise"; enabled: ed.canUndo; opacity: enabled ? 1 : 0.4; width: tools.cell; height: tools.cell; onAct: ed.undo()
                   onContainsMouseChanged: win.hint = containsMouse ? "Undo · Ctrl+Z" : "" }
            Tile { wide: false; icon: "arrow-clockwise"; enabled: ed.canRedo; opacity: enabled ? 1 : 0.4; width: tools.cell; height: tools.cell; onAct: ed.redo()
                   onContainsMouseChanged: win.hint = containsMouse ? "Redo · Ctrl+Y" : "" }
            Sep {}
            Tile { wide: false; icon: "copy"; width: tools.cell; height: tools.cell; onAct: win.finishEdit(true)
                   onContainsMouseChanged: win.hint = containsMouse ? "Copy only · Ctrl+C" : "" }
            Tile { wide: false; icon: "floppy-disk"; width: tools.cell; height: tools.cell; onAct: win.finishEdit(false)
                   onContainsMouseChanged: win.hint = containsMouse ? "Save · Enter" : "" }
            Tile { wide: false; icon: "x"; width: tools.cell; height: tools.cell; onAct: root.cancel()
                   onContainsMouseChanged: win.hint = containsMouse ? "Close · Esc" : "" }
          }
          Row {
            spacing: tools.gap
            Repeater {
              model: [Theme.red, Theme.yellow, Theme.green, Theme.accent, Theme.text, "#1b1b1b"]
              Cell {
                required property var modelData
                on: Qt.colorEqual(root.edColor, modelData)
                onClicked: root.edColor = modelData
                onContainsMouseChanged: win.hint = containsMouse ? "Colour" : ""
                Rectangle { anchors.centerIn: parent; width: Math.round(tools.cell * 0.5); height: width; radius: Theme.radiusInner; color: parent.parent.modelData
                            border.width: 1; border.color: Theme.line }
              }
            }
            Sep {}
            Item {   // size of the stroke and of the text: drag, or wheel over the picture, or + / -
              width: 7 * tools.cell + 4 * tools.gap - 18; height: tools.cell
              KnoblessSlider {
                anchors.verticalCenter: parent.verticalCenter; width: parent.width
                from: 1; to: 40; stepSize: 1; unit: "px"; value: root.edSize
                onMoved: v => root.edSize = v
              }
            }
            Sep {}
            Tile { wide: false; icon: "paint-bucket"; on: root.edFill; width: tools.cell; height: tools.cell; onAct: root.edFill = !root.edFill
                   onContainsMouseChanged: win.hint = containsMouse ? (root.edFill ? "Shapes filled" : "Shapes outlined") : "" }
          }
        }
      }

      Rectangle {   // the hovered tile's name, under the drop (above it with a bottom bar)
        visible: win.hint !== "" && tools.opened
        x: Math.round(tools.x + (tools.width - width) / 2)
        y: Prefs.barPosition === "bottom" ? tools.y - height - 6 : tools.y + tools.height + 6
        width: hintText.implicitWidth + 14; height: hintText.implicitHeight + 8; radius: Theme.radiusInner
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92); border.width: 1; border.color: Theme.line
        Text { id: hintText; anchors.centerIn: parent; text: win.hint; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(11 * Theme.scale) }
      }

      Item {
        id: keys
        focus: true; Component.onCompleted: forceActiveFocus()
        Keys.onEscapePressed: root.cancel()
        Keys.onPressed: e => {
          if (win.editing) {
            const ctrl = e.modifiers & Qt.ControlModifier
            const t = { [Qt.Key_B]: "brush", [Qt.Key_L]: "line", [Qt.Key_A]: "arrow", [Qt.Key_R]: "rect", [Qt.Key_E]: "ellipse",
                        [Qt.Key_T]: "text", [Qt.Key_N]: "num", [Qt.Key_H]: "mark", [Qt.Key_P]: "pixel" }[e.key]
            if (ctrl && e.key === Qt.Key_Z) { if (e.modifiers & Qt.ShiftModifier) ed.redo(); else ed.undo() }
            else if (ctrl && e.key === Qt.Key_Y) ed.redo()
            else if (ctrl && e.key === Qt.Key_C) win.finishEdit(true)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || (ctrl && e.key === Qt.Key_S)) win.finishEdit(false)
            else if (t && !ctrl) root.edTool = t
            else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) root.edSize = Math.min(40, root.edSize + 1)
            else if (e.key === Qt.Key_Minus) root.edSize = Math.max(1, root.edSize - 1)
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {   // Tab walks the tools
              const L = ["brush", "line", "arrow", "rect", "ellipse", "text", "num", "mark", "pixel"], i = L.indexOf(root.edTool)
              root.edTool = L[(i + (e.key === Qt.Key_Backtab ? -1 : 1) + L.length) % L.length]
            }
            else return
            e.accepted = true; return
          }
          if (root.editBusy || (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
          if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) { root.cycleMode(e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier) ? -1 : 1); e.accepted = true; return }
          if (root.mode === "window" || root.mode === "screen") {   // arrows choose, Enter captures
            if (e.key === Qt.Key_Down) { win.moveSel(1); e.accepted = true; return }
            if (e.key === Qt.Key_Up) { win.moveSel(-1); e.accepted = true; return }
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.confirm(); e.accepted = true; return }
          }
          const k = { [Qt.Key_A]: "shot", [Qt.Key_D]: "draw", [Qt.Key_G]: "gif", [Qt.Key_W]: "window", [Qt.Key_S]: "screen" }[e.key]
          if (k) { win.tool(k); e.accepted = true }
        }
      }
    }
  }

  // recording pill: a corner of the recorded output that the region does not cover; click = stop
  Variants {
    model: rec.running ? Quickshell.screens.filter(s => s.name === root.recOut) : []
    PanelWindow {
      id: pill
      required property var modelData
      screen: modelData
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "lwts-rec"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      implicitWidth: 104; implicitHeight: 30
      readonly property int m: 12
      function hits(cx, cy) { const r = root.recRect; return !(cx + implicitWidth <= r.x || cx >= r.x + r.width || cy + implicitHeight <= r.y || cy >= r.y + r.height) }
      readonly property var corner: {   // [right?, bottom?] of the first corner the region does not cover
        const W = modelData.width, H = modelData.height, c = [[false, false], [true, false], [false, true], [true, true]];
        for (const k of c) { const x = k[0] ? W - implicitWidth - m : m, y = k[1] ? H - implicitHeight - m : m; if (!hits(x, y)) return k }
        return c[1]
      }
      anchors { top: !corner[1]; bottom: corner[1]; left: !corner[0]; right: corner[0] }
      margins { top: m; bottom: m; left: m; right: m }
      Rectangle {
        anchors.fill: parent; radius: Theme.radiusCard; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92); border.width: 1; border.color: Theme.line
        Row {
          anchors.centerIn: parent; spacing: 8
          Rectangle { width: 10; height: 10; radius: 5; color: Theme.red; anchors.verticalCenter: parent.verticalCenter
                      SequentialAnimation on opacity { running: true; loops: Animation.Infinite; NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 } } }
          Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.text; font.family: Theme.font; font.pixelSize: Math.round(12 * Theme.scale)
                 text: { const t = Math.max(0, Math.floor((root.nowMs - root.recSince) / 1000)); return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0") + "  ■" } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stopRec() }
      }
    }
  }
}
