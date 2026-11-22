// Top bar (LWTS_SPEC 3; Nothing look: 26 px). Left: dot-matrix time + red dot | workspace dots | media. Centre: window title. Right: layout, dot
// (notifications; right click = tray), sound, network, clock. Mic, BT, night light, caffeine, AI live in Quick settings. Floating plate; flush with the screen in game mode.
// Clicks that open a panel only emit `panel(name, x)`: popups (step 5) own the panels, the bar owns nothing else.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.core
import qs.services
import qs.widgets

PanelWindow {
  id: bar
  signal panel(string name, real x)   // x: centre of the clicked module in screen coordinates
  signal menu(var handle, real x)     // tray app menu as a drop (popups/TrayMenuPanel.qml)
  signal quick()                     // a popup asks for the launcher the way the hotkey opens it (same place, not under the cursor)
  signal launch()                    // right click on the bar (not on a module with its own) = launcher
  readonly property int unread: Notifs.unread
  readonly property int urgency: Notifs.urgency   // 0 low, 1 normal, 2 critical

  visible: Prefs.ready && !remap
  anchors { top: Prefs.barPosition !== "bottom"; bottom: Prefs.barPosition === "bottom"; left: true; right: true }
  readonly property int edge: Theme.flush ? 0 : Math.max(2, Math.round(Theme.gap / 3))   // top margin follows the gaps (12 -> 4)
  margins { top: edge; bottom: edge; left: Theme.flush ? 0 : Theme.gap; right: Theme.flush ? 0 : Theme.gap }
  // the window also hosts the drops (launcher, popups): one surface = one blur, no seam where they join the bar
  readonly property int barH: Prefs.barHeight
  property bool hostOpen: false        // a drop is out: the window grows down (up for a bottom bar) to hold it
  property bool grab: false            // keyboard to the open drop
  // launcher <-> shade (Tab): the closing drop hands the keyboard to the opening one; dropping Exclusive even for one
  // tick gave the window under the shell the keyboard for 80-300 ms and the first key went there. Cleared by the opener.
  property bool handoff: false
  onHandoffChanged: if (handoff) handoffEnd.restart()
  Timer { id: handoffEnd; interval: 1500; onTriggered: bar.handoff = false }   // safety net: the opener never came
  // drops register themselves; the open one opens the frame (notch) and joins the input mask
  property Item launcherDrop: null
  property bool popupFlying: false      // the time drop carries the time (Popups); hides the same blocks as clockFlying
  property bool clockFlying: false     // the launcher carries the bar's time into its search row (launcher v2): the bar's date + time hide meanwhile
  readonly property Item clockItem: clockText
  property Item popupDrop: null
  property Item toastDrop: null        // notification pop-ups, under the dot (can be out together with another drop)
  readonly property Item dropItem: launcherDrop && launcherDrop.opened ? launcherDrop : popupDrop && popupDrop.opened ? popupDrop : null
  readonly property Item toastItem: toastDrop && toastDrop.opened ? toastDrop : null
  readonly property real toastX: toastItem ? toastItem.x : 0
  readonly property real toastW: toastItem ? toastItem.width : 0
  // a drop flush with an end of the bar squares that corner of the bar (the edge goes straight down)
  readonly property bool squareLeft: [dropItem, toastItem].some(d => !!d && d.flushLeft)
  readonly property bool squareRight: [dropItem, toastItem].some(d => !!d && d.flushRight)
  readonly property real dotX: dot.mapToItem(strip, dot.width / 2, 0).x
  property string popupPanel: ""

  implicitHeight: barH + 760   // constant: resizing the layer surface on every open / close flickers
  exclusiveZone: Session.barHidden ? -1 : barH   // Smart Hide (settings_spec 3.2): no reserved space while hidden
  mask: Region { item: bar.appearV > 0.01 ? strip : null; Region { item: bar.dropItem } Region { item: bar.toastItem } Region { item: bar.catchClicks && bar.lift ? catcher : null } }
  // over a fullscreen window: the launcher re-creates this surface straight on Overlay (a live surface changing layer does not get
  // the keyboard), and the whole surface takes input so a click outside the drop closes it (ClickAway sits on Bottom, under the video)
  property bool remap: false
  property bool catchClicks: false
  signal clickedAway()
  // over a fullscreen window the bar strip slides in / out with the drop (it is on Overlay only while a drop is out)
  property real appearV: 1
  Behavior on appearV { enabled: bar.overFs; NumberAnimation { id: appearAnim; duration: Motion.normal; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve
    onRunningChanged: if (!running) bar.maybeRelease() } }
  // open: the strip slides in first (Launcher.fsShow gives it its 250 ms), then the drop grows out of it; close: the drop folds
  // into the strip, then the strip slides out, and only then the surface goes back under the video (Top)
  // A surface under a fullscreen window gets no frame callbacks, so it renders nothing there. Moving it to Overlay and starting the
  // animations at once makes them run (time-based) before the first frame: the bar pops in with a delay and no animation. So the
  // animations wait until frames are really ticking on Overlay (FrameAnimation = the window's frame clock), then overlayReady() fires.
  property bool remapping: false
  property int framesSeen: 0
  signal overlayReady()
  function remapOverlay() {
    releaseFs.stop();
    if (remapping) return;
    if (overFs || fsPre) { overFs = true; appearV = 1; overlayReady(); return }   // already on Overlay (pre-lifted): nothing to wait for
    remapping = true; appearV = 0; overFs = true; framesSeen = 0; frameWatch.running = true; remapFallback.restart()
  }
  function finishRemap() { if (!remapping) return; remapping = false; frameWatch.running = false; remapFallback.stop(); appearV = 1; overlayReady() }
  FrameAnimation { id: frameWatch; running: false; onTriggered: { if (++bar.framesSeen >= 3) bar.finishRemap() } }
  Timer { id: remapFallback; interval: 600; onTriggered: bar.finishRemap() }   // no frames at all: go on anyway
  function maybeRelease() { if (overFs && !remapping && appearV === 0 && !lift && !appearAnim.running) { overFs = false; if (!bar.fsHere) fsPre = false; appearV = bar.fsHere ? 0 : 1 } }   // stays invisible under the video: the last committed buffer must not be a visible strip
  // Moving a surface that sits under a fullscreen window to Overlay takes 0.1 - 1 s (no frame callbacks there), so the drop's animation ran
  // before anything was on screen. So the bar is lifted to Overlay AHEAD, as soon as a fullscreen window is focused (strip invisible,
  // out of the input mask), and a launcher / popup then finds it ready. Not in game mode (an extra surface above a game costs direct scanout).
  property bool fsPre: false
  // The bar lives on ONE monitor: a fullscreen window on another monitor (focus follows the mouse) must not hide it - only a fullscreen
  // window focused on THIS bar's output counts (OsdState.fullscreenFocused alone is global: the focused window of whichever output).
  readonly property bool fsHere: OsdState.fullscreenFocused && Compositor.focusedOutput === (bar.screen ? bar.screen.name : "")
  onFsHereChanged: {
    if (bar.lift || bar.remapping) return;
    if (bar.fsHere) { if (!bar.fsPre && !Theme.game) { bar.appearV = 0; bar.fsPre = true } }
    else { bar.fsPre = false; if (!bar.overFs) bar.appearV = 1 }
  }
  MouseArea { id: catcher; anchors.fill: parent; z: -1; acceptedButtons: Qt.AllButtons; onPressed: bar.clickedAway() }
  // niri: OnDemand focus comes only on click and Top sits under fullscreen windows, so while a drop is open
  // (launcher, popups, quick settings) the bar is Overlay + Exclusive; clicks outside are caught by ClickAway
  property var optsSource: null         // the open picker (Launcher.qml binds it): its options replace the window title in the middle
  property bool holdKeys: false        // kept for the picker (Launcher.qml binds it); Exclusive is now on for every open drop
  // Latched: a grab takes the keyboard from the window, niri then reports no focused window and fullscreenFocused
  // goes false at once - the bar would drop back under the video. So the state is read ONCE when a drop opens and
  // kept until it is gone (+ 500 ms for the close animation).
  property bool overFs: false
  readonly property bool lift: grab || handoff || !!dropItem
  onLiftChanged: { if (lift) { releaseFs.stop(); if (!overFs && bar.fsHere) remapOverlay(); else if (overFs) appearV = 1 } else { releaseFs.restart(); maybeRelease() } }
  readonly property bool shown: !!dropItem
  onShownChanged: if (overFs) appearV = shown ? 1 : 0
  Timer { id: releaseFs; interval: 1000; onTriggered: { bar.overFs = false; bar.appearV = 1 } }   // safety net only
  WlrLayershell.layer: overFs || fsPre ? WlrLayer.Overlay : WlrLayer.Top   // Top sits under a fullscreen window, but niri draws no blur on Overlay: Overlay only over fullscreen
  WlrLayershell.keyboardFocus: grab || handoff ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  color: "transparent"
  WlrLayershell.namespace: "waybar"
  // glass (ext-background-effect): blur only behind the plate and the open drops' bodies, with their corners
  BackgroundEffect.blurRegion: Prefs.blurOn ? blurShape : null
  Region {
    id: blurShape
    item: strip.visible && bar.appearV >= 1 ? plate : null   // no blur under a strip that is sliding out / not yet in (a blur strip stayed behind)
    topLeftRadius: plate.topLeftRadius; topRightRadius: plate.topRightRadius
    bottomLeftRadius: plate.bottomLeftRadius; bottomRightRadius: plate.bottomRightRadius
    Region {
      readonly property Item d: bar.dropItem
      item: d ? d.body : null
      topLeftRadius: d ? d.rTop : 0; topRightRadius: topLeftRadius
      bottomLeftRadius: d ? d.rBottom : 0; bottomRightRadius: bottomLeftRadius
    }
    Region {
      readonly property Item d: bar.toastItem
      item: d ? d.body : null
      topLeftRadius: d ? d.rTop : 0; topRightRadius: topLeftRadius
      bottomLeftRadius: d ? d.rBottom : 0; bottomRightRadius: bottomLeftRadius
    }
  }
  screen: Quickshell.screens.find(s => s.name === Prefs.get("primary_monitor", "")) || Quickshell.screens.find(s => s.name === "DP-2" || s.name === "eDP-1") || Quickshell.screens[0]

  function xFor(name) {   // bar-window x of the module a hotkey opens under (-1 = centre; also a hidden module)
    const it = ({ audio: sound, net: sysGroup, bt: sysGroup, power: sysGroup, stats: sysGroup, notif: dot, clock: clockArea, time: clockArea, sysmon: title, layout: layoutArea, session: sessionBtn })[name];
    return it && it.visible ? it.mapToItem(strip, it.width / 2, 0).x : -1;
  }
  // clock click routing (settings.toml: time_panel = "combined" | "split", time_swap = false)
  //  combined: any click opens calendar + notifications in one drop; split: left = calendar, right = notifications; swap flips them
  readonly property bool timeCombined: Prefs.get("time_panel", "combined") !== "split"
  function timeClick(right) {
    if (timeCombined) return panel("time", xOf(clockArea))
    const swap = Prefs.get("time_swap", false) === true
    panel((right !== swap) ? "notif" : "clock", xOf(clockArea))
  }
  function xOf(item) { return item.mapToItem(null, item.width / 2, 0).x + bar.margins.left }

  // notch: a drop (launcher, popups) flows out of the bar here - the border opens over that span (bar coordinates)
  readonly property real notchX: dropItem ? dropItem.x : 0
  readonly property real notchW: dropItem ? dropItem.width : 0
  component Label: Text {   // Nothing: every bar text is mono capitals (Theme.label), a size below the bar font
    font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Theme.barPx - 2; font.letterSpacing: 0
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
  }
  component Divider: Rectangle { implicitWidth: 1; implicitHeight: 12; color: Theme.line }
  // icon button: tint/fill for "on", left/right click and wheel handled by the user of it
  component Button: MouseArea {
    id: b
    property string icon
    property bool on: false
    property color tint: on ? Theme.accent : Theme.text
    implicitWidth: 22; implicitHeight: bar.barH
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    Icon { anchors.centerIn: parent; name: b.icon; fill: b.on; color: b.tint }
  }

  Item {   // the bar itself; the rest of the window is room for drops
    id: strip
    visible: !Session.barHidden   // Smart Hide (settings_spec 3.2): gone while the active window is fullscreen
    width: parent.width; height: bar.barH
    opacity: bar.appearV
    transform: Translate { y: (1 - bar.appearV) * (Prefs.barPosition === "bottom" ? 1 : -1) * (bar.barH + 8) }
    y: Prefs.barPosition === "bottom" ? parent.height - height : 0
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: bar.launch() }   // under the modules
    Rectangle {   // the plate (corner towards a flush drop: square)
      id: plate
      width: parent.width; height: parent.height
      radius: Theme.flush ? 0 : Theme.radius
      readonly property bool down: Prefs.barPosition !== "bottom"
      bottomLeftRadius: down && bar.squareLeft ? 0 : radius;  topLeftRadius: !down && bar.squareLeft ? 0 : radius
      bottomRightRadius: down && bar.squareRight ? 0 : radius; topRightRadius: !down && bar.squareRight ? 0 : radius
      color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
    }
    // screen corners (settings_spec 3.4, end-4 style): at 0 bar gap, concave fillets join the bar to the side
    // edges of the screen. Visual only - outside the input mask, clicks go to the windows below.
    Repeater {
      model: Theme.gap === 0 && Theme.barGapRounded && !Theme.lite && Theme.radius > 0 ? [0, 1] : []
      Shape {
        required property int modelData
        readonly property bool rightSide: modelData === 1
        readonly property bool atTop: Prefs.barPosition !== "bottom"
        readonly property int r: Theme.radius
        visible: !(rightSide ? bar.squareRight : bar.squareLeft)   // a drop flush with that end takes the corner
        width: r; height: r
        x: rightSide ? strip.width - r : 0
        y: atTop ? strip.height : -r
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.x: r / 2; origin.y: r / 2; xScale: rightSide ? -1 : 1; yScale: atTop ? 1 : -1 }
        ShapePath {
          strokeWidth: -1
          fillColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
          startX: 0; startY: 0
          PathLine { x: r; y: 0 }
          PathArc { x: 0; y: r; radiusX: r; radiusY: r; direction: PathArc.Counterclockwise }
          PathLine { x: 0; y: 0 }
        }
      }
    }
    Item {   // 1px frame, open where drops are attached: clipped copies of one Rectangle frame (cheap per frame)
      id: frame
      visible: !Theme.flush
      width: parent.width; height: parent.height
      transform: Scale { yScale: Prefs.barPosition === "bottom" ? -1 : 1; origin.y: bar.barH / 2 }
      // [from, to, open] pieces along the bottom edge: open pieces have no bottom line
      readonly property var pieces: {
        const gaps = [[bar.notchX, bar.notchX + bar.notchW], [bar.toastX, bar.toastX + bar.toastW]]
                       .filter(g => g[1] > g[0]).map(g => [Math.max(0, Math.min(width, g[0])), Math.max(0, Math.min(width, g[1]))])
                       .sort((p, q) => p[0] - q[0]);
        const out = []; let x = 0;
        for (const g of gaps) { const a = Math.max(x, g[0]); if (a > x) out.push([x, a, false]); if (g[1] > a) out.push([a, g[1], true]); x = Math.max(x, g[1]) }
        out.push([x, width, false]);
        return out;
      }
      Repeater {
        model: frame.pieces
        Item {
          required property var modelData
          clip: true
          x: modelData[0]; width: modelData[1] - modelData[0]; height: frame.height - (modelData[2] ? 1 : 0)
          Rectangle { x: -parent.x; width: frame.width; height: frame.height; radius: Theme.radius
                      bottomLeftRadius: bar.squareLeft ? 0 : radius; bottomRightRadius: bar.squareRight ? 0 : radius
                      color: "transparent"; border.width: 1; border.color: Theme.line }
        }
      }
    }


    RowLayout {   // left (end-4 skeleton, Nothing look): workspace dots | the active window
      anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
      spacing: 20
      Row {
        visible: Prefs.module("hyprland/workspaces")
        spacing: 6
        Repeater {
          model: Compositor.workspacesOn(bar.screen ? bar.screen.name : "").length   // a count, not objects: delegates survive focus changes, so Behavior can animate
          Rectangle {
            required property int index
            readonly property var ws: Compositor.workspacesOn(bar.screen ? bar.screen.name : "")[index] || ({ idx: index + 1, active: false })
            property var modelData: ws
            anchors.verticalCenter: parent.verticalCenter
            // active = a solid dot that stretches into a bar (the old LWTS look, redone Nothing-crisp: integer px, no overshoot); others = hollow rings
            width: modelData.active ? 20 : 6; height: 6; radius: 3
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
            color: modelData.active ? Theme.text : "transparent"
            border.width: modelData.active ? 0 : 1; border.color: Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.8)
            Behavior on color { ColorAnimation { duration: Theme.game ? 0 : 60 } }
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Compositor.focusWorkspace(modelData.idx) }
          }
        }
      }

      MouseArea {   // left: active window title; click = SysMon
        id: title
        visible: Prefs.module("hyprland/window")
        implicitWidth: Math.min(titleText.implicitWidth, 260); implicitHeight: bar.barH
        cursorShape: Qt.PointingHandCursor
        onClicked: bar.panel("sysmon", bar.xOf(title))
        Label {
          id: titleText
          anchors.fill: parent
          horizontalAlignment: Text.AlignLeft
          elide: Text.ElideRight
          opacity: 0.75   // one weight for every bar text (layout, clock, title, media)
          text: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.title : ""
        }
      }
    }

    RowLayout {   // centre: the dot-matrix time (the bar's hero); hidden while a picker shows its options here
      anchors.centerIn: parent
      visible: !bar.optsSource
      spacing: 20
    MouseArea {   // clock: click = calendar. Dot-matrix time as the bar's hero, the red Nothing dot after it
        id: clockArea
        // the time drop keeps this clock where it is (same spot as in the launcher: the drop hangs under it and shows only the date + calendar)
        implicitWidth: clockRow.implicitWidth + 4; implicitHeight: bar.barH
        clip: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => bar.timeClick(m.button === Qt.RightButton)
        Row {
          id: clockRow; anchors.verticalCenter: parent.verticalCenter; spacing: 3
          Label { anchors.verticalCenter: parent.verticalCenter; color: Theme.dim; text: Qt.formatDateTime(clock.date, "ddd dd MMM")
                  opacity: (bar.clockFlying || bar.popupFlying) ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } } }   // date lives with the time (one block, one click = calendar)
          Item { width: 5; height: 1 }   // air between the date and the time
          UiNum { id: clockText; anchors.verticalCenter: parent.verticalCenter
                  opacity: (bar.clockFlying || bar.popupFlying) ? 0 : 1   // instant: the launcher's copy takes over at the same spot
                  text: Qt.formatDateTime(clock.date, (Prefs.get("clock_24h", true) ? "HH:mm" : "h:mm AP") + (Prefs.get("clock_seconds", false) ? ":ss" : "")) }
          Rectangle {   // the red Nothing dot = unread notifications: lit only while there are some, click = notification centre
            id: unreadDot
            anchors.top: clockText.top; anchors.topMargin: 1; width: 4; height: 4; radius: 2; color: Theme.red
            opacity: bar.unread > 0 && !(bar.clockFlying || bar.popupFlying) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.duration } }
            MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: bar.unread > 0; cursorShape: Qt.PointingHandCursor
                        onClicked: bar.timeCombined ? bar.panel("time", bar.xOf(clockArea)) : bar.panel("notif", bar.xOf(clockArea)) }
          }
        }
        SystemClock { id: clock; precision: Prefs.get("clock_seconds", false) ? SystemClock.Seconds : SystemClock.Minutes }
      }
    }

    Loader {   // picker options (Dark and light apart | Tint) while the wallpaper / palette picker is open
      active: !!bar.optsSource
      anchors.centerIn: parent
      sourceComponent: PickerOpts { picker: bar.optsSource; compact: true }
    }

    RowLayout {   // right: live activities, layout, the dot (notifications / tray), status icons VOL / NET / BT / BAT
      anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
      spacing: 2

      Repeater {   // live activities from modules (Modules.activities): a pill with a draining ring, slides in and out
        model: Modules.activities
        Item {
          id: act
          required property var modelData
          readonly property bool shown: modelData.visible()
          implicitHeight: bar.barH
          implicitWidth: shown ? pill.width + 8 : 0
          opacity: shown ? 1 : 0
          clip: true
          Behavior on implicitWidth { NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
          Behavior on opacity { NumberAnimation { duration: Motion.dropOpen } }
          MouseArea {
            id: pill
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: pillRow.implicitWidth + 14; height: Math.round(bar.barH * 0.72)
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => { if (m.button === Qt.RightButton && act.modelData.alt) act.modelData.alt(); else if (act.modelData.panel) bar.panel(act.modelData.panel, bar.xOf(pill)) }
            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.tint }
            Row {
              id: pillRow
              anchors.centerIn: parent
              spacing: 6
              Item {   // the ring drains clockwise from the top; repainted once a second at most (the value changes per second)
                id: ring
                width: Math.round(Theme.barPx * 1.15); height: width
                anchors.verticalCenter: parent.verticalCenter
                readonly property real p: act.modelData.progress()
                ProgressRing { anchors.centerIn: parent; d: ring.width; p: ring.p }
                Icon { anchors.centerIn: parent; name: act.modelData.icon(); color: Theme.accent; fill: true; font.pixelSize: Math.round(ring.width * 0.5) }
              }
              Label { anchors.verticalCenter: parent.verticalCenter; text: act.modelData.text(); color: Theme.accent
                      font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            }
          }
        }
      }
      MouseArea {   // screen sharing: a tiny red caption while a screencast runs (like MIC by VOL); click = STOP? (2 s), click again = stop it
        id: castInd
        readonly property bool shown: Compositor.castCount > 0
        property bool armed: false
        implicitHeight: bar.barH
        implicitWidth: shown ? castText.implicitWidth + 10 : 0
        opacity: shown ? 1 : 0
        clip: true
        cursorShape: Qt.PointingHandCursor
        onShownChanged: armed = false
        Behavior on implicitWidth { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.dropCurve } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Timer { id: disarm; interval: 2000; onTriggered: castInd.armed = false }
        onClicked: { if (!armed) { armed = true; disarm.restart() } else { armed = false; Compositor.stopCasts() } }
        Label { id: castText; anchors.centerIn: parent; text: castInd.armed ? "STOP?" : "CAST"; color: Theme.red }
      }
      MouseArea {   // layout: click = next
        id: layoutArea
        visible: Prefs.module("hyprland/language")
        implicitWidth: layoutText.implicitWidth + 10; implicitHeight: bar.barH
        cursorShape: Qt.PointingHandCursor
        onClicked: Keyboard.switchNext()
        Label { id: layoutText; anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: Keyboard.current || Keyboard.name   // two letters in the dot-matrix font, like the clock; -1 px: the dot face sits low in its box
                font.family: Theme.dot; font.pixelSize: Math.round(11 * Theme.scale) + 4; font.hintingPreference: Font.PreferNoHinting }
      }
      MouseArea {   // the tray handle (three dots): click = tray icons slide out / fold. Notifications belong to the clock (its red dot, click = calendar + notifications)
        id: dot
        visible: SystemTray.items.values.length > 0   // no tray items, no handle
        property bool trayOpen: false
        Connections { target: Compositor; function onFocusedWorkspaceIdChanged() { dot.trayOpen = false } }
        implicitWidth: dotRow.implicitWidth + 14; implicitHeight: bar.barH
        cursorShape: Qt.PointingHandCursor
        onClicked: trayOpen = !trayOpen
        Row {
          id: dotRow
          anchors.centerIn: parent
          spacing: 8
          Row {   // the handle: three small dots, lit while the tray is open
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 3; Rectangle { width: 2; height: 2; radius: 1; color: dot.trayOpen ? Theme.text : Theme.dim } }
          }
          Item {
            clip: true; height: bar.barH
            width: dot.trayOpen ? tray.implicitWidth : 0
            Behavior on width { NumberAnimation { duration: Motion.duration; easing.type: Motion.type; easing.bezierCurve: Motion.curve } }
            Row {
              id: tray
              anchors.verticalCenter: parent.verticalCenter
              Repeater {   // tray: left = open the app (menu if it has nothing else), right = its menu, middle = secondary action
                model: SystemTray.items
                MouseArea {
                  id: item
                  required property var modelData
                  implicitWidth: 22; implicitHeight: bar.barH
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                  onClicked: m => {
                    if (m.button === Qt.MiddleButton) modelData.secondaryActivate();
                    else if (modelData.hasMenu && (m.button === Qt.RightButton || modelData.onlyMenu)) bar.menu(modelData.menu, bar.xOf(item));
                    else modelData.activate();
                  }
                  AppIcon { anchors.centerIn: parent; source: item.modelData.icon; tray: item.modelData }   // one ink for every tray icon, colour only as a signal (widgets/AppIcon.qml)

                }
              }
            }
          }
        }
      }
      UiStat {   // sound (Nothing: "VOL 64" / "VOL MUTE", text: it carries a number): click = panel, right = mute, wheel = volume
        id: sound
        implicitHeight: bar.barH
        key: "Vol"
        num: !Audio.muted; value: Audio.muted ? "Mute" : String(Math.round(Audio.volume * 100))
        tint: Audio.muted ? Theme.red : Theme.text
        onClicked: m => m.button === Qt.RightButton ? Audio.toggleMute() : bar.panel("audio", bar.xOf(sound))
        onWheel: w => Audio.step(w.angleDelta.y > 0 ? 0.05 : -0.05)
        Text {   // microphone muted: a tiny red caption in the corner (nothing shows while the mic is live)
          visible: Audio.micMuted
          text: "MIC"; color: Theme.red; font.family: Theme.label; font.pixelSize: Math.round(7 * Theme.scale)
          anchors { right: parent.right; top: parent.top; topMargin: 2; rightMargin: 2 }
        }
      }
      Row {   // status icons: network, Bluetooth, battery. One group = one anchor: the System drop (SystemPanel) opens under it on the clicked category
        id: sysGroup
        UiStat {   // network (Nothing: "NET ETH" / "NET WIFI" / "NET OFF" in red)
          id: net
          readonly property var dev: Networking.devices.values.find(d => d.connected)
          implicitHeight: bar.barH
          icon: dev && dev.type !== DeviceType.Wifi ? "network" : "wifi-high"; badge: dev ? "transparent" : Theme.red
          num: false; value: !dev ? "Off" : dev.type === DeviceType.Wifi ? "Wifi" : "Eth"
          tint: dev ? Theme.text : Theme.dim
          onClicked: bar.panel("net", bar.xOf(sysGroup))
        }
        UiStat {   // bluetooth: only while there's an adapter ("BT ON" / "BT OFF")
          id: bt
          visible: !!Bluetooth.defaultAdapter
          implicitHeight: bar.barH
          icon: "bluetooth"; badge: Bluetooth.devices.values.some(d => d.connected) ? Theme.accent : "transparent"
          num: false; value: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "On" : "Off"
          tint: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? Theme.text : Theme.dim
          onClicked: bar.panel("bt", bar.xOf(sysGroup))
        }
        MouseArea {   // desktop (no battery): icon + two vertical dot columns fill from the bottom, CPU left, GPU right; click = Stats category of the System drop
          id: stats
          readonly property bool on: !(Session.bat && Session.bat.isLaptopBattery)
          visible: on
          Component.onCompleted: SysMon.barWants = Qt.binding(() => stats.on && bar.visible)
          implicitHeight: bar.barH; implicitWidth: statCols.implicitWidth + 8
          cursorShape: Qt.PointingHandCursor
          onClicked: bar.panel("stats", bar.xOf(sysGroup))
          Row {
            id: statCols
            anchors.centerIn: parent; spacing: 2
            Repeater {   // CPU column | icon | GPU column
              model: [{ v: SysMon.cpu }, { icon: true }, { v: SysMon.gpu }]
              Loader {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: modelData.icon ? statIcon : statColumn
                property real level: modelData.v || 0
              }
            }
          }
          Component { id: statIcon; Icon { name: "cpu"; color: Theme.text } }
          Component {
            id: statColumn
            Column {   // 5 dots, filled from the bottom; red above 90 %
              spacing: 1
              Repeater {
                model: 5
                Rectangle {
                  required property int index
                  readonly property real lit: parent.parent.level * 5 - (4 - index) >= 0.5 ? 1 : 0   // index 4 = bottom dot
                  width: 4; height: 2; radius: 1
                  color: lit > 0 && parent.parent.level > 0.9 ? Theme.red : Theme.text
                  opacity: 0.16 + 0.84 * lit
                }
              }
            }
          }
        }
        UiStat {   // battery: laptop only ("BAT 81"; red at 15 % and below while discharging)
          id: battery
          readonly property var dev: Session.bat
          readonly property bool low: !!dev && dev.isLaptopBattery && dev.state === UPowerDeviceState.Discharging && dev.percentage * 100 <= 15
          visible: !!dev && dev.isLaptopBattery
          implicitHeight: bar.barH
          icon: "battery-full"; showValue: true; badge: low ? Theme.red : dev && dev.state === UPowerDeviceState.Charging ? Theme.accent : "transparent"
          value: dev ? String(Math.round(dev.percentage * 100)) : ""
          tint: Theme.text
          onClicked: bar.panel("power", bar.xOf(sysGroup))
        }
      }
      MouseArea {   // session button, the right corner: a 3x3 dot matrix (no power icon). Rest = the centre cross dim, hover = the cross lit, open = all nine in the accent.
                    // A power timer running / paused: the time left in the dot font to the left of the dots (accent running, dim paused), the cross lit.
        id: sessionBtn
        readonly property bool open: bar.popupPanel === "session"
        readonly property var tmr: Tiles.all.powertimer ? Tiles.all.powertimer.api : null   // the module's own PowerTimer instance
        readonly property bool timer: !!tmr && (tmr.on || tmr.paused)
        readonly property bool running: !!tmr && tmr.on
        readonly property bool paused: !!tmr && tmr.paused && !tmr.on
        // the dots tell the state at a glance: idle = the cross (dim; lit on hover); open = all nine; a timer running = the checkerboard inverts every second
        // (accent for Sleep, RED for Power off); paused = a pause sign (two bars, dim)
        readonly property color tone: open ? Theme.accent : running ? (tmr.action === "poweroff" ? Theme.red : Theme.accent) : paused ? Theme.dim : Theme.text
        readonly property int tick: running ? tmr.left % 2 : 0   // flips every second: the checkerboard inverts (a ticking clock)
        implicitWidth: sessRow.implicitWidth + 14; implicitHeight: bar.barH
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: bar.panel("session", bar.xOf(sessionBtn))
        Row {
          id: sessRow
          anchors.centerIn: parent
          spacing: 7
          Text {
            visible: sessionBtn.timer
            anchors.verticalCenter: parent.verticalCenter
            text: !sessionBtn.tmr ? "" : sessionBtn.tmr.paused ? sessionBtn.tmr.clock(sessionBtn.tmr.pausedSec) : sessionBtn.tmr.leftText
            color: sessionBtn.paused ? Theme.dim : sessionBtn.tone
            font.family: Theme.dot; font.pixelSize: Math.round(11 * Theme.scale) + 4; font.features: { "tnum": 1 }; font.hintingPreference: Font.PreferNoHinting
          }
          Grid {
            anchors.verticalCenter: parent.verticalCenter
            columns: 3; spacing: 2
            Repeater {
              model: 9
              Rectangle {
                required property int index
                readonly property bool cross: index % 2 === 1 || index === 4   // N, W, E, S + the centre
                width: 3; height: 3; radius: 1.5
                color: sessionBtn.tone
                opacity: sessionBtn.open ? 1
                         : sessionBtn.running ? ((Math.floor(index / 3) + index % 3) % 2 === sessionBtn.tick ? 1 : 0.16)
                         : sessionBtn.paused ? (index % 3 !== 1 ? 0.9 : 0.16)
                         : cross ? (sessionBtn.containsMouse ? 1 : 0.55) : (sessionBtn.containsMouse ? 0.5 : 0.16)
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
              }
            }
          }
        }
      }
    }
  }
}