// Bar pop-ups: one drop under the clicked icon, its content switches with the panel (sound, network + Bluetooth in one "system" drop,
// SysMon, calendar, notification centre). Lives inside the bar window like the launcher (one surface, no seam).
// Second click on the same icon / Esc / click outside / workspace switch closes; so does the cursor leaving the
// drop and its icon for 1 s (a drop opened from the keyboard starts counting only once the cursor has touched it). Hotkeys: Super+Alt+S/W/B, Super+N.
import QtQuick
import Quickshell
import qs.core
import qs.widgets
import qs.services
import qs.launcher

Item {
  id: host
  required property var bar
  visible: false
  anchors.fill: parent
  property string panel: ""
  property real anchorX: -1   // centre of the icon, bar-window px; -1 = centre
  property bool closingNow: false
  property bool pinned: false   // the System drop's pin: click-away / mouse-leave / keyboard grab are off until unpinned or closed
  property string sysTab: "net"   // the names "net" / "bt" / "power" / "stats" are one drop ("system", SystemPanel) opened on that category
  readonly property var widths: ({ audio: 360, sysmon: 360, clock: 232, notif: 380, ai: 520, media: 360, tray: 160, traylist: 240 })
  readonly property bool atBottom: Prefs.barPosition === "bottom"
  // the time drops (notifications + calendar) carry the launcher's header: the bar's time flies into the strip above the drop and grows, the date sits on the left
  readonly property bool headerOn: ["time", "clock", "notif"].includes(panel) && !atBottom   // stays while closing: the time flies back into the bar
  readonly property bool flyWant: headerOn && !closingNow
  readonly property int headH: Math.round(40 * Theme.scale)
  readonly property int headPad: ["time", "clock", "notif"].includes(panel) && !atBottom ? Math.max(0, 3 + headH - bar.barH - 4) : 0   // the content starts under the header
  property real fly: 0   // 0 = the time sits in the bar, 1 = in the header
  NumberAnimation on fly { id: flyAnim; running: false; duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.curve }
  function flyTo(v) { flyAnim.stop(); flyAnim.to = v; flyAnim.from = fly; flyAnim.start() }
  onFlyWantChanged: flyTo(flyWant ? 1 : 0)
  Binding { target: host.bar; property: "popupFlying"; value: host.visible && ["time", "clock", "notif"].includes(host.panel) && !host.atBottom }   // a flag of its own: two Bindings on one property reset each other at the Tab handoff

  property var menuHandle: null   // tray app menu shown by the "tray" drop
  function openMenu(handle, x) {   // right click on a tray icon: same icon again closes, another one switches
    if (visible && !closingNow && panel === "tray" && menuHandle === handle) { close(); return }
    menuHandle = handle; open("tray", x);
  }
  function toggle(name, x) {
    if ((name === "net" || name === "bt" || name === "power" || name === "stats") && visible && !closingNow && panel === "system") {   // same category = close, the other = switch the tab
      if (sysTab === name) close(); else { sysTab = name; if (loader.item && loader.item.setTab) loader.item.setTab(name) }
      return
    }
    if (visible && !closingNow && panel === name) close(); else open(name, x)
  }
  function open(name, x) {
    if (name === "net" || name === "bt" || name === "power" || name === "stats") { sysTab = name; name = "system" }
    if (name !== "system") pinned = false;
    panel = name; anchorX = x; closingNow = false; handingOff = false;
    bar.grab = !pinned; bar.handoff = false; visible = true; drop.open();
    (loader.item && loader.item.wantsKeys ? loader.item : keys).forceActiveFocus();   // panels with own keys (media, tray menu)
  }
  property bool handingOff: false   // closing for the launcher (Tab): its header takes over, this one goes at once
  function close(handoff) { if (!visible || closingNow) return; handingOff = !!handoff; closingNow = true; if (handoff) bar.handoff = true; bar.grab = false; drop.close() }   // handoff: the launcher takes the keyboard next
  ClickAway { windows: [host.bar]; active: drop.settled && !host.closingNow && !host.pinned; onCleared: host.close() }
  Connections { target: Compositor; function onFocusedWorkspaceIdChanged() { host.close() } }
  Component.onCompleted: bar.popupDrop = drop
  Binding { target: host.bar; property: "popupPanel"; value: host.panel }

  Item { id: keys; focus: true; Keys.onEscapePressed: host.close() }

  // cursor away from the drop and its bar icon for 1 s -> close (not a panel with keepOpen, e.g. the AI chat: it is typed in)
  HoverHandler { id: hover }   // the whole bar window under an open drop takes input: test the drop's rect
  readonly property bool near: {
    if (!hover.hovered) return false;
    const pt = hover.point.position;
    const onStrip = atBottom ? pt.y > height - bar.barH - 8 : pt.y < bar.barH + 8;
    if (onStrip) return anchorX >= 0 && Math.abs(pt.x - anchorX) < 60;
    return pt.x >= drop.x - 8 && pt.x <= drop.x + drop.width + 8 && pt.y >= drop.y - 8 && pt.y <= drop.y + drop.height + 8;
  }
  property bool armed: false
  onNearChanged: if (near) { armed = true; leave.stop() } else if (armed && visible && !(loader.item && loader.item.keepOpen)) leave.restart()
  Timer { id: leave; interval: 1000; onTriggered: if (!host.near) host.close() }
  onVisibleChanged: if (!visible) { armed = false; leave.stop(); pinned = false }
  Connections { target: loader.item; ignoreUnknownSignals: true; function onCloseMe() { host.close() }
    function onQuick() { host.close(true); bar.quick() }   // a panel asks for the launcher (Tab in the time shade)
    function onPinChanged(v) { host.pinned = v; if (host.visible && !host.closingNow) { bar.grab = !v; if (!v) (loader.item && loader.item.wantsKeys ? loader.item : keys).forceActiveFocus() } }
    function onShowMenu(handle) { host.menuHandle = handle; host.panel = "tray"; Qt.callLater(() => { if (loader.item) loader.item.forceActiveFocus() }) } }   // tray list -> that app's menu   // AI chat: Esc / close button

  Droplet {
    id: drop
    flip: host.atBottom
    fullWidth: host.panel === "tray" && loader.item ? Math.max(host.widths.tray, loader.item.implicitWidth + 24) : loader.item && loader.item.dropWidth ? loader.item.dropWidth : host.widths[host.panel] || 360
    fullHeight: (loader.item ? loader.item.implicitHeight : 80) + 24 + host.headPad
    onClosed: { host.visible = false; host.closingNow = false; host.panel = "" }
    Behavior on fullWidth { enabled: drop.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
    Behavior on fullHeight { enabled: drop.settled && !(loader.item && loader.item.resizing); NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
    anchorX: host.anchorX   // under the module; flush with a bar end only when it does not fit (Droplet)
    Behavior on x { enabled: drop.settled; NumberAnimation { duration: Motion.dropOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dropCurve } }
    y: host.atBottom ? host.height - host.bar.barH - height : host.bar.barH

    Loader {
      id: loader
      x: 12; y: 12 + host.headPad; width: drop.fullWidth - 24
      source: ({ audio: "AudioPanel.qml", system: "SystemPanel.qml", sysmon: "SysMonPanel.qml",
                 clock: "CalendarPanel.qml", time: "TimePanel.qml", notif: "NotifCenter.qml", media: "MediaPanel.qml", tray: "TrayMenuPanel.qml", traylist: "TrayListPanel.qml", session: "SessionPanel.qml" })[host.panel] || Modules.panelUrl(host.panel)
      onItemChanged: {
        if (!item) return;
        item.width = Qt.binding(() => loader.width);
        if (item.tab !== undefined && host.panel === "system") item.tab = host.sysTab;
        if (item.menu !== undefined) item.menu = Qt.binding(() => host.menuHandle);
        if (item.maxHeight !== undefined) item.maxHeight = Qt.binding(() => host.height - host.bar.barH - 32);   // the bar window holds the drop: never taller
      }
    }
  }

  QtObject { id: headSrc; readonly property real fly: host.fly; readonly property var bar: host.bar; readonly property bool typing: false }   // what LaunchHeader reads from a launcher
  LaunchHeader {   // over the bar strip and the top of the drop (same header as the launcher)
    launcher: headSrc
    visible: host.headerOn && drop.opened && !host.handingOff
    x: drop.x + 24; width: drop.width - 48
    y: 3
    height: host.headH
  }
}
