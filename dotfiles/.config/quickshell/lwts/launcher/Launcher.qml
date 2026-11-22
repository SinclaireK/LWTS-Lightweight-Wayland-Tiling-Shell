// Launcher (Super+Space): a drop out of the bar — at the bar's centre or under the cursor 
// = "center" | "cursor"). Focus always stays in the input: empty = Quick settings, typing = apps + calculator,
// Backspace to empty = Quick settings again. Esc / click outside / workspace switch / Super+Space closes.
// Search: ↑ ↓ select, Enter launch (calculator: copy), Ctrl+P / right click pin.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.core
import qs.services
import qs.widgets
import qs.settings

// Lives inside the bar window (bar.hostOpen grows it): the drop and the bar are one surface, one blur, no seam.
Item {
  id: win
  required property var home     // the bar window
  property var floater: null     // FloatHost: used when the cursor is on a monitor without the bar
  property var bar: home         // the current host; open() moves the launcher between the two
  signal details(string panel)   // a tile asked for its panel (popups, step 5)
  visible: false
  anchors.fill: parent
  // click anywhere else = close (Hyprland focus grab on the bar window)
  // active once the drop has settled: a grab started while the window is still resizing is cleared at once
  Connections {   // fullscreen plate: the ClickAway plate sits on Bottom, under the video, so the host catches the click itself
    target: win.bar
    enabled: !!win.bar.catchClicks && drop.settled && !win.closingNow && !win.wsGuard
    function onClickedAway() { if (win.picker !== "") win.pickerView?.cancel(); else win.close() }
  }
  ClickAway { windows: [win.bar]; active: drop.settled && !win.closingNow && win.picker === "" && !win.wsGuard; onCleared: win.close() }   // not while the picker moves workspaces
  // Settings close like the launcher: Esc, the gear, or a click outside (no × button)

  readonly property bool atBottom: Prefs.barPosition === "bottom"
  property bool settings: false
  // settings: adaptive compact - a share of the screen, within sane limits (2560x1440 -> 900x620, 1920x1080 -> 806x594)
  readonly property int settingsW: Math.max(760, Math.min(1040, Math.round((bar.screen ? bar.screen.width : 1920) * 0.5)))   // v5: wide window - six tabs and long rows fit without scrolling or paging   // was up to 900: rows left a wide empty middle; tabs scroll instead
  readonly property int settingsH: Math.max(520, Math.min(740, Math.round((bar.screen ? bar.screen.height : 1080) * 0.7)))   // the bar surface is barH + 760 tall: stay inside it (bar on top or bottom)
  readonly property bool typing: query.text !== ""   // anything typed (search or Settings filter): the header's date and time fade, the field takes the full width
  // the time shade (calendar + notifications) is a mode of this very drop: Tab from Quick settings morphs the drop into it, no second drop
  property bool timeMode: false
  property bool timeOpen: false   // asked by open(): applied in show()
  readonly property bool searching: !settings && !timeMode && query.text !== ""
  readonly property string mode: timeMode ? "time" : settings ? "settings" : searching ? "search" : "quick"
  readonly property real timeW: timeLoader.item ? timeLoader.item.dropWidth + 8 : 420   // the panel's drop width counts 12 px margins, here 16. Until the time page is loaded the drop stays at the Quick settings width (the old 620 placeholder laid the Quick page out at 620 inside a 420 drop after a Tab: the cut-off chips / dots bug)
  function focusMain() { if (timeMode) { if (timeLoader.item) timeLoader.item.forceActiveFocus() } else query.forceActiveFocus() }
  // pages of the drop: Quick settings (search / Settings live there), Notifications (+ calendar), Notes; the header's pager and Tab step through them
  readonly property var pageIds: Modules.enabled("notes") ? ["quick", "notif", "notes"] : ["quick", "notif"]
  readonly property var pageNames: ({ quick: "Quick settings", notif: "Notifications", notes: "Notes" })
  property string timePage: "notif"
  readonly property string page: timeMode ? timePage : "quick"
  function setPage(id) { if (id === "quick") setTime(false); else { timePage = id; setTime(true) } }
  function pageStep(d) { const n = pageIds.length; setPage(pageIds[(Math.max(0, pageIds.indexOf(page)) + d + n) % n]) }
  function setTime(v) { if (timeMode === v || !visible || closingNow) return; timeMode = v; query.text = ""; Qt.callLater(focusMain) }
  function toggleTime(ax) { if (visible && !closingNow) { if (timeMode) close(); else setPage("notif") } else { timePage = "notif"; open(true, ax, true) } }
  // preview strip (Settings -> Wallpaper / Palette): windows go to an empty workspace and come back afterwards
  ClickAway { windows: [win.bar]; active: drop.settled && !win.closingNow && win.picker !== "" && !win.wsGuard; onCleared: win.pickerView?.cancel() }   // picker: a click on the desktop / another window = back to Settings (the preview is undone), not close
  property string picker: ""
  readonly property var pickerView: pickerLoader.item
  readonly property var settingsPage: settingsLoader.item
  property bool settingsWarm: false
  // settingsWarm stays false: pre-building Settings cost ~41 MB resident
  property int savedWs: -1
  property bool wsGuard: false
  readonly property string mon: bar.screen ? bar.screen.name : ""
  function openPicker(k) {   // on the bar's monitor, whichever monitor has focus
    savedWs = Compositor.focusedWorkspace ? Compositor.focusedWorkspace.idx : -1;
    picker = k; pickerView.start(k);
    wsGuard = true;
    // go to the empty workspace niri always keeps last on this monitor, so the wallpaper shows without windows in front
    Compositor.act(["focus-monitor", mon]); Compositor.focusWorkspace(Compositor.lastIdx(mon));
  }
  function closePicker() {
    if (picker === "") return;
    picker = ""; query.forceActiveFocus();   // keys back to the input (the strip had them)
    if (savedWs > 0) { wsGuard = true; Compositor.focusWorkspace(savedWs) }
    guardOff.restart();
  }
  Timer { id: guardOff; interval: 600; onTriggered: win.wsGuard = false }
  Binding { target: win.bar; property: "optsSource"; value: win.pickerView; when: win.picker !== "" && !win.bar.floating }   // the picker's options live in the bar
  Binding { target: win.bar; property: "holdKeys"; value: win.picker !== "" || win.wsGuard || refocus.running }
  // after Hyprland applies a setting / reloads, take the keyboard back for a moment (Exclusive), then OnDemand again
  Timer { id: refocus; interval: 1200 }
  Connections { target: Look; function onHyprTouched() { if (win.visible) { refocus.restart(); query.forceActiveFocus() } } }
  function toggleSettings() { settings = !settings; query.text = ""; settingsPage?.reset(); query.forceActiveFocus() }
  readonly property bool headerOn: !bar.floating && !atBottom   // the concept header on the bar strip (a plate / bottom bar keeps the clock in the search row)
  readonly property int headH: Math.round(40 * Theme.scale)
  // the search row never glides: when its place or width changes (first letter, Settings on/off) it fades out, jumps, fades back in
  readonly property real edgeL: drop.x   // left edge of the panel: pop-up cards step aside to the left of it
  property real swap: 1
  property int swapPause: 0
  SequentialAnimation {
    id: swapAnim
    PropertyAction { target: win; property: "swap"; value: 0 }
    PauseAnimation { duration: win.swapPause }
    NumberAnimation { target: win; property: "swap"; to: 1; duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve }
  }
  onTypingChanged: { swapPause = 0; swapAnim.restart() }
  onSettingsChanged: { swapPause = Math.round(Motion.dropOpen * 0.75); swapAnim.restart() }   // wait until the drop has changed size
  property real fly: 0   // 0 = the time sits in the bar, 1 = in the search row
  NumberAnimation on fly { id: flyAnim; running: false; duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.curve }
  function flyTo(v) { flyAnim.stop(); flyAnim.to = v; flyAnim.from = fly; flyAnim.start() }
  Binding { target: win.bar; property: "clockFlying"; value: win.visible && !win.bar.floating }
  property real anchorX: -1   // centre of the drop, local px; -1 = screen centre
  property int sel: 0
  readonly property var apps: searching ? Apps.search(query.text).slice(0, 8) : []
  readonly property int rows: (Calc.result ? 1 : 0) + apps.length

  function toggle(fromBar) { visible && !closingNow ? close() : open(fromBar) }
  property bool closingNow: false
  // `launcher_position` (Settings -> Bar & launcher -> Opens): a drop out of the bar at its centre / left / right /
  // under the cursor, or a floating plate at the cursor / the screen centre. A monitor without the bar always gets a
  // plate at the cursor; a right click on the bar (fromBar) always gets a drop.
  function open(fromBar, ax, time) {
    if (visible && !closingNow) return;
    timeOpen = !!time;
    query.text = ""; sel = 0; settings = false; settingsPage?.reset(); quick.reset();
    const pos = Prefs.get("launcher_position", "center");
    const plateMode = pos === "plate" || pos === "screen";
    const fs = OsdState.fullscreenFocused;   // over a fullscreen window the bar window cannot be lifted reliably (keys went to the video): a fresh Overlay plate
    Pointer.locate((x, y) => {
      const s = Quickshell.screens.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height);
      const onBarScreen = !!s && !!home.screen && s.name === home.screen.name;
      win.host(s && floater && (!onBarScreen || (plateMode && !fromBar)) ? floater : home, s);
      home.catchClicks = fs; if (floater) floater.catchClicks = fs;
      if (bar.floating) {
        if (pos === "screen" && onBarScreen) { anchorX = -1; bar.cy = Math.round(s.height * 0.3) + 30 }
        else { anchorX = x - s.x; bar.cy = y - s.y }
      } else if (pos === "left") anchorX = 0;
      else if (pos === "right") anchorX = width;
      else if (pos === "center" && !fromBar) anchorX = -1;
      else { const lx = x - bar.screen.x - bar.margins.left; anchorX = lx >= 0 && lx <= width ? lx : -1 }
      if (time && ax >= 0 && !bar.floating) anchorX = ax;   // the time shade hangs under the clock
      if (fs && !bar.floating) { fsShow.restart(); home.remapOverlay() } else win.show();
    });
  }
  Timer { id: fsShow; interval: 700; onTriggered: win.show() }   // fallback; normally the bar's overlayReady (frames are ticking on Overlay) shows it
  Connections { target: win.home; function onOverlayReady() { if (fsShow.running) { fsShow.stop(); win.show() } } }   // after the bar surface is back (on Overlay)
  function search(t) { open(); query.text = t }
  function openSettings(section) {
    if (typeof section === "string" && isNaN(Number(section))) { openSettingsId(section); return }
    open(); settingsLoader.asynchronous = false; if (!settings) toggleSettings(); settingsLoader.asynchronous = true;
    if (section > 0 && settingsPage) settingsPage.section = section
  }
  function openSettingsId(id) {
    open(); settingsLoader.asynchronous = false; if (!settings) toggleSettings(); settingsLoader.asynchronous = true;
    if (id && settingsPage) {
      let idx = (settingsPage.sections || []).findIndex(s => s.id === id);
      if (idx < 0 && id === "wifi") idx = (settingsPage.sections || []).findIndex(s => s.id === "network");
      if (idx >= 0) settingsPage.section = idx;
    }
  }
  // over a fullscreen video the keyboard goes back to it only after Esc is released (the browser sees the held key on focus-in and leaves fullscreen)
  Timer { id: grabOff; interval: 220; onTriggered: win.bar.grab = false }
  property bool handingOff: false   // closing for the time drop (Tab): its own header takes over, so this one goes at once (no second date / time on top)
  function show() { grabOff.stop(); handingOff = false; fly = 0; flyTo(1); closingNow = false; bar.hostOpen = true; bar.grab = true; home.handoff = false; timeMode = timeOpen; visible = true; query.forceActiveFocus(); if (timeMode) Qt.callLater(focusMain); drop.open() }
  function close(handoff) { if (!visible || closingNow) return; handingOff = !!handoff; flyTo(0); if (picker !== "") pickerView?.cancel(); closingNow = true; if (handoff && bar === home) { grabOff.stop(); home.handoff = true; bar.grab = false } else if (bar.overFs) grabOff.restart(); else bar.grab = false; drop.close() }
  // the bar opens its bottom border where the drop flows out of it
  Component.onCompleted: bar.launcherDrop = drop   // the bar opens its frame where the drop flows out
  function host(h, s) {   // move to the bar window or to the floating one (on screen s)
    if (h.floating) h.screen = s;
    if (h === bar) return;
    bar.launcherDrop = null; bar.grab = false;
    bar = h; parent = h.contentItem; h.launcherDrop = drop;
  }
  Connections { target: Compositor; function onFocusedWorkspaceIdChanged() { if (win.picker === "" && !win.wsGuard && !win.settings) win.close() } }

  function launch(i) {
    if (Calc.result && i === 0) { Calc.copy(); close(); return }
    const a = apps[i - (Calc.result ? 1 : 0)];
    if (a) { Apps.launch(a); close() }
  }

  Droplet {
    id: drop
    readonly property real targetW: win.picker !== "" ? Math.min(win.width - 2 * Theme.gap, 920) : win.timeMode ? win.timeW : win.settings ? win.settingsW : 420
    fullWidth: targetW
    contentWidth: targetW   // Tab quick <-> settings: the settings page laid out per frame at 60 Hz was the stutter
    // size changes (Tab, search, picker) glide without overshoot: a spring here grew past the target and shrank back
    Behavior on fullWidth { enabled: drop.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.curve } }
    fullHeight: content.implicitHeight + 32
    onClosed: { win.home.catchClicks = false; if (win.floater) win.floater.catchClicks = false; win.visible = false; win.closingNow = false; if (win.bar.floating) win.bar.hostOpen = false }
    flip: win.atBottom && !win.bar.floating
    plate: !!win.bar.floating
    Behavior on fullHeight { enabled: drop.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.curve } }
    anchorX: win.anchorX   // under the cursor; flush with a bar end only when it does not fit (Droplet)
    y: win.bar.floating ? Math.max(8, Math.min(win.height - fullHeight - 8, win.bar.cy - 30))   // top just above the cursor: it lands on the input, the plate grows down
     : win.atBottom ? win.height - win.bar.barH - height : win.bar.barH

    ColumnLayout {
      id: content
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }   // Nothing: more air
      spacing: 12

      Item { visible: win.picker === "" && !win.headerOn; Layout.fillWidth: true; Layout.preferredHeight: 26 }   // the search row floats above (root level); this keeps its place in the drop when there is no header

      Rectangle {   // Nothing: the search field is a line, not a box
        visible: win.picker === ""
        Layout.fillWidth: true; Layout.topMargin: win.headerOn ? 4 : -6; Layout.bottomMargin: win.headerOn ? -4 : 0; implicitHeight: 1; color: Theme.edge
      }

      Loader {   // built only while open (Settings + Picker held ~66 MB idle)
        id: pickerLoader
        active: win.picker !== ""
        visible: active
        Layout.fillWidth: true
        Layout.topMargin: win.picker !== "" ? -10 : 0   // the collapsed input row leaves its spacing: top and bottom gaps of the picker equal
        sourceComponent: Picker { optsInBar: !win.bar.floating; onDone: win.closePicker() }
      }

      Loader {
        id: settingsLoader
        // built once in the background after start and kept: Tab then knows the page height at once (it grew to settingsH
        // and shrank back while loading) and nothing is built mid-animation (the stutter)
        active: win.settings || win.settingsWarm
        asynchronous: true   // 2300 lines of QML: built synchronously it froze the width animation
        visible: win.settings && win.picker === ""
        Layout.fillWidth: true
        Layout.preferredHeight: item ? Math.min(win.settingsH, item.wantedHeight) : win.settingsH
        sourceComponent: SettingsNew {
          onPick: k => win.openPicker(k)
          onRefocus: query.forceActiveFocus()
          filter: win.settings ? query.text : ""
        }
      }

      Loader {   // the time shade: calendar + notifications (popups/TimePanel.qml), built only in this mode
        id: timeLoader
        active: win.timeMode
        visible: active
        Layout.fillWidth: true
        source: "../popups/TimePanel.qml"
        onLoaded: { item.width = Qt.binding(() => timeLoader.width); item.tab = Qt.binding(() => win.timePage); if (win.timeMode) item.forceActiveFocus() }
      }
      Connections { target: timeLoader.item; ignoreUnknownSignals: true
        function onCloseMe() { win.close() }
        function onPage(d) { win.pageStep(d) } }   // Tab / Shift+Tab: the next / previous page, the same drop morphs

      QuickSettings {
        id: quick
        visible: win.mode === "quick"
        Layout.fillWidth: true
        onCloseRequested: win.close()
        onDetails: p => { win.close(true); win.details(p) }
      }

      Column {   // results: calculator first, then apps
        visible: win.searching && win.rows > 0
        Layout.fillWidth: true
        spacing: 4
        Repeater {
          model: win.rows
          MouseArea {
            id: row
            required property int index
            readonly property bool isCalc: !!Calc.result && index === 0
            readonly property var app: isCalc ? null : win.apps[index - (Calc.result ? 1 : 0)]
            width: parent.width; height: 28
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: win.sel = index
            onClicked: m => { if (m.button === Qt.RightButton) { if (app) Apps.togglePin(app) } else win.launch(index) }
            Row {   // Nothing: no grey plate for the picked row - its dot lights up and the name turns white
              anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
              spacing: 9
              Rectangle {   // the calculator row: a dot marks the picked row (lit = accent, off = faint)
                visible: row.isCalc
                anchors.verticalCenter: parent.verticalCenter
                width: 4; height: 4; radius: 2
                color: win.sel === row.index ? Theme.accent : Theme.dim
                opacity: win.sel === row.index ? 1 : 0.35
              }
              AppIcon {   // an app: its own icon as a dot matrix; lit = picked. No icon in the theme: the kind glyph below
                id: appPic
                property string src: row.app ? (Quickshell.iconPath(row.app.icon || "", true) || "file:///usr/share/icons/Adwaita/scalable/mimetypes/application-x-executable.svg") : ""   // an app with no icon of its own: the theme's generic one
                visible: !row.isCalc && src !== ""
                anchors.verticalCenter: parent.verticalCenter
                source: src; size: 26
                ink: win.sel === row.index ? Theme.accent : Theme.text
                opacity: win.sel === row.index ? 1 : 0.7
              }
              UiKindIcon {   // an app without an icon: its kind as a dot glyph (browser, game, terminal ...); lit = picked
                visible: !row.isCalc && appPic.src === ""
                anchors.verticalCenter: parent.verticalCenter
                kind: row.app ? Kinds.ofEntry(row.app) : "other"
                color: win.sel === row.index ? Theme.accent : Theme.text
                opacity: win.sel === row.index ? 1 : 0.6
                faint: 0.14
              }
              UiNum {   // calculator result: Doto numerals
                visible: row.isCalc
                anchors.verticalCenter: parent.verticalCenter
                text: "= " + Calc.result; color: Theme.accent; font.pixelSize: Math.round(15 * Theme.scale)
              }
              Text {
                visible: !row.isCalc
                anchors.verticalCenter: parent.verticalCenter
                text: row.app ? row.app.name : ""
                color: win.sel === row.index ? Theme.text : Theme.dim
                font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(12 * Theme.scale)   // Nothing: mono caps list
              }
            }
            Rectangle {   // pinned: a small square instead of the pin icon
              visible: !!row.app && Apps.pinned(row.app)
              width: 4; height: 4; color: Theme.dim
              anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter } }
          }
        }
      }
      Text {
        visible: win.searching && win.rows === 0
        text: "Nothing found"
        color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(12 * Theme.scale)
      }
    }
  }
  RowLayout {   // input with a morphing mode icon. Root level: with the header it sits between the date and the time (on the bar strip),
                // otherwise it takes the place of the first row in the drop. The picker collapses it but keeps it alive (an invisible input loses the keyboard)
    id: searchRow
    readonly property real hx: drop.x + (win.headerOn ? 24 : 16)   // header: same left edge as the rows' text (16 + 8)
    readonly property real hw: drop.width - (win.headerOn ? 48 : 32)
    x: win.headerOn && !win.typing ? hx + hdr.dateW + 16 : hx
    y: win.headerOn ? 3 + (win.headH - 26) / 2 : drop.y + 16
    width: win.headerOn && !win.typing ? Math.max(90, hw - hdr.dateW - hdr.clockW - 32) : hw
    height: win.picker === "" ? 26 : 0
    opacity: (win.picker === "" && drop.opened && !win.timeMode ? 1 : 0) * win.swap
    enabled: !win.timeMode   // the time shade has no search: the hidden field must not take clicks or the keyboard
    clip: win.picker !== ""
    spacing: 9
        MouseArea {   // mode icon: Quick settings / Search / Settings morph into each other; click = Settings on / off
          implicitWidth: 18; implicitHeight: 18
          cursorShape: Qt.PointingHandCursor
          onClicked: win.toggleSettings()
          opacity: win.typing || win.settings ? 1 : 0   // empty field: no icon, no caret (the header carries the look); they appear with the first letter
          Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
          Repeater {
            model: [["squares-four", "quick"], ["magnifying-glass", "search"], ["gear", "settings"]]
            Icon {
              required property var modelData
              readonly property bool on: win.mode === modelData[1]
              anchors.centerIn: parent; name: modelData[0]; color: Theme.accent; font.pixelSize: 16
              opacity: on ? 1 : 0; rotation: on ? 0 : 90; scale: on ? 1 : 0.6
              Behavior on opacity { NumberAnimation { duration: Motion.duration } }
              Behavior on rotation { NumberAnimation { duration: Motion.duration * 1.6; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
              Behavior on scale { NumberAnimation { duration: Motion.duration } }
            }
          }
        }
        TextInput {
          id: query
          Layout.fillWidth: true
          font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(14 * Theme.scale)   // Nothing: mono caps input
          color: Theme.text
          selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
          cursorDelegate: Rectangle { width: 1; color: Theme.text; visible: win.typing || win.settings }
          clip: true
          onTextChanged: { win.sel = 0; Calc.input = text }
          Text {   // placeholder
            visible: !query.text && win.settings
            text: "Filter settings"
            color: Theme.dim; font.family: Theme.label; font.capitalization: Font.AllUppercase; font.pixelSize: Math.round(12 * Theme.scale)   // Nothing: mono caps placeholder
          }
          Keys.onPressed: e => {
            if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) { if (win.picker !== "") pickerView.cancel(); else if (win.settings) win.toggleSettings(); else if (e.key === Qt.Key_Tab) { win.setPage("notif") } else win.toggleSettings() }   // in a picker Tab = back; Tab = the shade (calendar + notifications), Shift+Tab = Settings, Tab in Settings = back
            else if (win.picker !== "") { if (!pickerView.handleKey(e)) return }
            else if (win.settings) { if (!settingsPage?.handleKey(e)) { if (e.key === Qt.Key_Escape) win.close(); else return } }
            else if (e.key === Qt.Key_Escape && !(win.mode === "quick" && quick.inside)) win.close();
            else if (!win.searching) { if (!quick.handleKey(e)) return }
            else if (e.key === Qt.Key_Down) win.sel = Math.min(win.sel + 1, win.rows - 1);
            else if (e.key === Qt.Key_Up) win.sel = Math.max(win.sel - 1, 0);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.launch(win.sel);
            else if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) { const a = win.apps[win.sel - (Calc.result ? 1 : 0)]; if (a) Apps.togglePin(a) }
            else return;
            e.accepted = true;
          }
          Keys.onReleased: e => { if (win.mode === "quick") quick.handleRelease(e) }
        }

        Item {   // the bar's time, carried into the search row (launcher v2): slides from the bar's clock while the drop grows
          id: clockSlot
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: clockRow.implicitWidth; implicitHeight: clockRow.implicitHeight
          visible: win.picker === "" && !win.headerOn
          Row {
            id: clockRow
            spacing: 3
            readonly property var from: win.bar.floating || !win.bar.clockItem ? null : win.bar.clockItem.mapToItem(win, 0, 0)
            readonly property var to: clockSlot.mapToItem(win, 0, 0)
            transform: Translate { x: clockRow.from ? (clockRow.from.x - clockRow.to.x) * (1 - win.fly) : 0; y: clockRow.from ? (clockRow.from.y - clockRow.to.y) * (1 - win.fly) : 0 }
            opacity: clockRow.from ? 1 : win.fly
            SystemClock { id: lClock; precision: SystemClock.Minutes }
            UiNum { id: lNum; text: Qt.formatDateTime(lClock.date, (Prefs.get("clock_24h", true) ? "HH:mm" : "h:mm AP")) }
            Rectangle { y: 1; width: 4; height: 4; radius: 2; color: Theme.red; opacity: win.bar.unread > 0 ? 1 : 0 }   // unread dot travels with the time
          }
        }
      }

  ShadePager {   // between the date and the time: the page name, one dot per page, arrows (Quick settings: while the field is empty; it takes the place when typing)
    x: win.headerOn ? searchRow.hx + hdr.dateW + 16 : searchRow.hx
    y: searchRow.y - 1
    width: win.headerOn ? Math.max(90, searchRow.hw - hdr.dateW - hdr.clockW - 32) : searchRow.hw
    visible: opacity > 0
    opacity: win.picker === "" && !win.settings && drop.opened && (win.timeMode || (win.headerOn && !win.typing)) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.type; easing.bezierCurve: Motion.fadeCurve } }
    text: win.pageNames[win.page]
    count: win.pageIds.length
    index: Math.max(0, win.pageIds.indexOf(win.page))
    onStep: d => win.pageStep(d)
  }
  LaunchHeader {   // over the bar strip and the top of the drop
    id: hdr
    launcher: win
    visible: win.headerOn && win.picker === "" && drop.opened && !win.handingOff
    x: drop.x + 24; width: drop.width - 48
    y: 3
    height: win.headH
  }
}
