// The lock screen's stage: a plate that grows out of the bar to nearly the whole screen (and folds back into it), with margins
// from the screen edges. The blurred wallpaper covers the whole screen; the plate is the bar-like fill on it; the content fades in
// late and stays still. Shared by LockScreen.qml (real) and LockPreview.qml (a window).
import QtQuick
import qs.core
import qs.services
import qs.widgets

Item {
  id: st
  property url shot: ""            // a screenshot to start from (LockPreview only): the first frame, so nothing changes before the bar grows
  property string screenName: ""   // which screen's cached pictures to show (services/Lock.qml); "" = the live wallpaper
  property bool veil: false        // the after-unlock veil: no sharp first frame; blur and base fade out while the plate folds into the bar
  property bool plain: false       // a monitor without the bar: only the blur, no plate
  property bool hideContent: false // true: the content (clock, field) goes first, the plate and blur stay
  property bool driven: false      // the lock opening: k and f follow Lock.openK / Lock.openF (one progress shared with the other stage)
  property bool opened: false     // the owner flips this: true = grown, false = folded into the bar
  default property alias content: host.data

  // where the bar is, as the bar draws itself (bar/Bar.qml): same margins, height and side
  readonly property bool atBottom: Prefs.barPosition === "bottom"
  readonly property real barH: Prefs.barHeight
  readonly property real barX: Theme.flush ? 0 : Theme.gap
  readonly property real edge: Theme.flush ? 0 : Math.max(2, Math.round(Theme.gap / 3))
  readonly property real barY: atBottom ? height - edge - barH : edge
  readonly property real m: Theme.flush ? 0 : Math.max(80, Theme.gap * 6)   // margin of the grown plate from the screen edges

  property real k: driven ? Lock.openK : opened ? 1 : 0
  readonly property int dur: Motion.fit(Motion.slow * Lock.anim)   // not Motion.speed: at 60 Hz the shorter run left ~13 frames for a screen-sized growth (read as low fps)
  // lock opening (veil mode) and the way back: the wallpaper fade (f) and the plate (k) run together
  // open = enter (felt smooth), fold = Motion rule 3: shorter, the emphasized curve (begins and ends on screen)
  Behavior on k { enabled: !st.driven; NumberAnimation { duration: st.opened ? st.dur : Motion.fit(st.dur * (1 + Motion.exitRatio) / 2); easing.type: Motion.type; easing.bezierCurve: st.opened ? [0.3, 0.1, 0.2, 1, 1, 1] : Motion.emphasized } }

  // Run fn after n frames of this window really reached the screen: a fresh lock surface / veil spends its first frames on texture
  // uploads and the blur layer (30-65 ms each on the laptop), so a motion started at once lost its first sixth. Fallback 300 ms.
  property var _after: null
  property int _left: 0
  function afterFrames(n, fn) { _after = fn; _left = n; afterSafety.restart(); if (st.Window.window) st.Window.window.update() }
  function _run() { const fn = _after; _after = null; afterSafety.stop(); if (fn) fn() }
  Connections { target: st._after ? st.Window.window : null; function onFrameSwapped() { if (--st._left <= 0) st._run(); else st.Window.window.update() } }
  Timer { id: afterSafety; interval: 300; onTriggered: st._run() }

  property real f: driven ? Lock.openF : opened ? 1 : 0   // wallpaper fade (veil mode) / the sharp wallpaper -> blur crossfade; symmetric curve: the decelerate one pops on opacity
  Behavior on f { enabled: !st.driven; NumberAnimation { duration: Motion.off ? 0 : Math.round((st.opened ? 520 : 400) * Lock.anim * Motion.slowmo); easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }

  readonly property real px: Math.round(barX + (m - barX) * k)   // whole px: sub-pixel edges crawl at 60 Hz
  readonly property real py: Math.round(barY + (m - barY) * k)
  readonly property real pw: Math.round((width - 2 * barX) + ((width - 2 * m) - (width - 2 * barX)) * k)
  readonly property real ph: Math.round(barH + ((height - 2 * m) - barH) * k)
  readonly property real pr: Theme.radius + (Theme.radiusCard * 2 - Theme.radius) * k

  Rectangle { anchors.fill: parent; color: Theme.surface; opacity: st.veil ? st.f : 1 }
  LockBackdrop { anchors.fill: parent; screenName: st.screenName; opacity: st.veil ? st.f : 1 }   // bigger than the screen: the blur's see-through edge is off screen   // the blurred wallpaper over the whole screen, margins included
  Image {   // first frame: the sharp wallpaper, so the lock starts at once (no screenshot); it melts into the blur as the plate grows
    anchors.fill: parent; fillMode: Image.PreserveAspectCrop; cache: st.shot == ""; opacity: 1 - st.f; visible: !st.veil
    source: st.shot != "" ? st.shot : Lock.sharpUrl(st.screenName)
    sourceSize: Qt.size(width, height)
  }

  Item {   // the plate with room around it
    id: plateFx
    readonly property real pad: 40
    visible: !st.plain
    x: st.px - pad; width: st.pw + 2 * pad
    y: st.atBottom ? st.py - pad : st.py; height: st.ph + pad
    opacity: Math.min(1, st.k * 6)   // the bar in the shot is still there at the start: the plate takes over within the first sixth
    Rectangle {   // the plate: the bar's translucent fill and hairline, grown from the bar
      x: plateFx.pad; y: st.atBottom ? plateFx.pad : 0
      width: st.pw; height: st.ph; radius: st.pr
      color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
      border.width: 1; border.color: Theme.line
    }
  }

  Item {   // the bar itself: its pixels from the shot ride on the plate's bar-side edge and fade out as the plate grows
    visible: st.shot != "" && !st.plain && opacity > 0
    x: st.px; width: st.pw; height: st.barH; clip: true
    y: st.atBottom ? st.py + st.ph - st.barH : st.py
    opacity: Math.max(0, 1 - st.k * 2.5)
    Image { x: -st.barX; y: -st.barY; width: st.width; height: st.height; source: st.shot; asynchronous: false; cache: false; fillMode: Image.PreserveAspectCrop }
  }

  Item {   // content: laid out for the grown plate, revealed from the half of the growth, gone first on the way back
    id: host
    x: st.m; y: st.m; width: st.width - 2 * st.m; height: st.height - 2 * st.m
    opacity: Math.max(0.003, Math.min(1, (st.k - 0.5) / 0.4)) * ck   // never fully 0 while shown: the text textures are made in the first (heavy) frame, not at the reveal
    property real ck: st.hideContent ? 0 : 1
    Behavior on ck { NumberAnimation { duration: Motion.off ? 0 : 120 * Motion.slowmo; easing.type: Easing.OutCubic } }
    visible: ck > 0
  }
}
