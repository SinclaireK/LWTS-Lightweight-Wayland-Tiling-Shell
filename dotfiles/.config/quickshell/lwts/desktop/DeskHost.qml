// Desktop widgets: one Bottom-layer surface per output that has widgets to show (state: services/Desk.qml). The surface covers the
// output but its input region is only the widget rectangles, so clicks everywhere else reach the compositor / the wallpaper.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services
import qs.widgets

Variants {
  model: Quickshell.screens.filter(s => Desk.shownList(s.name).length > 0 || Desk.menuOn)   // the menu needs the surface on every output
  PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "lwts-desk"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    readonly property var items: Desk.shownList(modelData.name)
    // input region = the widget rectangles only. Fixed slots bound to the list (a Region list built by an Instantiator stays empty = nothing
    // clickable; checked with WAYLAND_DEBUG): an unused slot is 0x0 and adds nothing. Up to 12 widgets per output.
    function g(i, k) { const p = items[i]; return !p ? 0 : k === "x" ? Desk.ox + Desk.pos(p.x) + Desk.inset : k === "y" ? Desk.oy + Desk.pos(p.y) + Desk.inset : k === "w" ? Desk.px(p.w) : Desk.px(p.h) }
    // With the desktop menu on the whole surface takes input (right click on the bare desktop); without it only the widget rectangles.
    mask: Desk.menuOn ? null : slotMask
    Region { id: slotMask; regions: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(i => slots.createObject(win, { i })) }
    Component { id: slots; Region { required property int i; x: win.g(i, "x"); y: win.g(i, "y"); width: win.g(i, "w"); height: win.g(i, "h") } }
    property var menu: null   // { x, y } while the desktop menu is open
    function openMenu(x, y, onIcon) { if (onIcon) Desk.fetchInfo(); menu = { x, y, onIcon: !!onIcon } }
    readonly property string mon: modelData.name
    Connections { target: Desk; function onTestMenu(mon, x, y, onIcon) { if (mon === win.mon) win.openMenu(x, y, onIcon) } }
    MouseArea {
      anchors.fill: parent; enabled: Desk.menuOn; acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: m => { if (m.button === Qt.RightButton) win.openMenu(m.x, m.y); else Desk.selection = [] }
    }
    Loader {   // Work mode: the desktop folder's files as icons on the desktop
      anchors.fill: parent; active: Desk.work && Desk.menuOn && win.mon === Desk.iconMon
      sourceComponent: DeskIconLayer { widgets: win.items; onItemMenu: (x, y) => win.openMenu(x, y, true) }
    }
    Repeater {
      model: win.items
      Loader {
        required property var modelData
        readonly property var def: Desk.def(modelData.wid)
        x: Desk.ox + Desk.pos(modelData.x) + Desk.inset; y: Desk.oy + Desk.pos(modelData.y) + Desk.inset
        width: Desk.px(modelData.w); height: Desk.px(modelData.h)
        source: def ? def.file : ""
        onLoaded: if (item) item.inst = modelData
      }
    }
    LazyLoader {   // the desktop context menu: its own surface above the windows (Overlay, exclusive keys) while it is open
      active: win.menu !== null
      PanelWindow {
        screen: win.modelData
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lwts-desk-menu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        UiMenu {
          anchors.fill: parent
          ax: win.menu ? win.menu.x : 0; ay: win.menu ? win.menu.y : 0
          items: !win.menu ? [] : win.menu.onIcon ? Desk.itemMenuItems() : Desk.menuItems(win.mon, win.menu.x, win.menu.y)
          onDone: win.menu = null
        }
      }
    }
  }
}
