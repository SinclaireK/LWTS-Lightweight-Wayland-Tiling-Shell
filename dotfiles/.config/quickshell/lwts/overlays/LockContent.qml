// What the lock screen shows (clock, password field, Caps Lock warning, player), shaped by the lock_* keys of Settings -> Appearance -> Lock screen.
// LockScreen.qml owns PAM and the session lock; this file only draws and reports the typed password through submit().
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs.core
import qs.services
import qs.widgets

Item {
  id: c
  property string error: ""
  property bool busy: false
  property int shake: 0
  property bool success: false      // the password was right: the dots fill up one by one, then LockScreen unlocks
  property int held: 0              // dots lit when Enter was pressed (the field is cleared at once)
  property real fillV: 0
  property bool ui: true            // draw the lock (the main monitor); the others keep only the hidden input
  onTypedChanged: if (typed !== "") held = typed.length   // also on the monitor that does not get the keys
  property alias typed: pw.text     // the typed password, shared between monitors by LockScreen
  signal submit(string pw)

  function opt(map, key, def) { const v = map[Prefs.get(key, def)]; return v === undefined ? map[def] : v }
  readonly property real k: opt({ small: 0.75, normal: 1, large: 1.35 }, "lock_scale", "normal")
  readonly property real fieldW: opt({ narrow: 220, normal: 280, wide: 360 }, "lock_input", "normal")
  readonly property string timeFmt: Prefs.get("lock_hour12", false) === true ? "h:mm" : "hh:mm"
  readonly property string dateFmt: opt({ "10 Oct": "d MMM", "10.10": "dd.MM", Saturday: "dddd", none: "" }, "lock_date", "10 Oct")
  readonly property bool showLayout: Prefs.get("lock_layout", true) !== false
  readonly property bool showBattery: Prefs.get("lock_battery", true) !== false
  readonly property var bat: UPower.displayDevice
  readonly property string hint: error !== "" ? error : (busy ? "Checking…" : Prefs.get("lock_hint", "Password"))
  property bool caps: false        // Caps Lock LED (any keyboard), read only while the lock is drawn

  onSuccessChanged: if (success) { fillV = Math.min(held, track0) / track0; fillAnim.restart() }
  property int track0: 20           // set by the stage from the real track
  NumberAnimation { id: fillAnim; target: c; property: "fillV"; to: 1; duration: Motion.off ? 0 : Math.round(c.fillMs); easing.type: Easing.Linear }
  readonly property real fillMs: 260 * Lock.anim * Motion.slowmo

  SystemClock { id: clock; precision: SystemClock.Minutes }
  Process { id: capsRead; command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
            stdout: StdioCollector { onStreamFinished: c.caps = text.split("\n").some(x => x.trim() !== "" && x.trim() !== "0") } }
  Timer { interval: 400; repeat: true; triggeredOnStart: true; running: c.ui && c.visible; onTriggered: if (!capsRead.running) capsRead.running = true }

  // the real input: invisible, always focused (a lock screen must never lose the keyboard); the plate only draws bullets
  TextInput {
    id: pw
    width: 1; height: 1; opacity: 0
    echoMode: TextInput.Password
    enabled: !c.busy && !c.success
    focus: true
    Component.onCompleted: forceActiveFocus()
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onReturnPressed: { c.submit(text); text = "" }
    Keys.onEnterPressed: { c.submit(text); text = "" }
    Keys.onEscapePressed: text = ""
    Connections { target: c; function onShakeChanged() { pw.text = ""; pw.forceActiveFocus() } }
  }
  Timer { interval: 300; repeat: true; running: c.visible && !pw.activeFocus; onTriggered: pw.forceActiveFocus() }   // lost it: take it back

  // ---- Nothing look: hero dot clock, dotted rules, the password as a row of dots, mono caps statuses. Sizes scale with lock_scale.
  readonly property string userName: Prefs.get("lock_user", true) === true ? (Quickshell.env("USER") || "").toUpperCase() : ""
  readonly property bool hasBat: showBattery && !!bat && bat.isLaptopBattery
  readonly property var player: MediaPick.player
  function fmt(sec) { sec = Math.max(0, Math.floor(sec)); return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0") }

  Component {
    id: lwts
    Item {
      id: stage
      readonly property int cap: Math.round(13 * c.k * Theme.scale)
      readonly property real w: Math.max(timeLine.width, 320)   // the one column everything under the clock is as wide as: the clock

      // top strip: state on the left, layout / battery on the right (mono caps, one red dot = unread)
      Row {
        anchors { left: parent.left; top: parent.top; margins: Math.round(28 * c.k) }
        spacing: 10
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: c.error !== "" ? Theme.red : Theme.text; opacity: c.error !== "" || c.busy ? 1 : 0.5 }
        UiCaption { anchors.verticalCenter: parent.verticalCenter; text: "Locked"; color: Theme.text; font.pixelSize: stage.cap }
        Rectangle { visible: Notifs.unread > 0; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.red }
        UiCaption { visible: Notifs.unread > 0; anchors.verticalCenter: parent.verticalCenter; text: Notifs.unread + " new"; font.pixelSize: stage.cap }
      }
      Row {
        anchors { right: parent.right; top: parent.top; margins: Math.round(28 * c.k) }
        spacing: 16
        UiCaption { visible: c.caps; anchors.verticalCenter: parent.verticalCenter; text: "Caps lock"; color: Theme.red; font.pixelSize: stage.cap }
        UiCaption { visible: c.showLayout && Keyboard.name !== ""; anchors.verticalCenter: parent.verticalCenter; text: Keyboard.name; font.pixelSize: stage.cap }
        Row {
          visible: c.hasBat; anchors.verticalCenter: parent.verticalCenter; spacing: 8
          DotMeter { anchors.verticalCenter: parent.verticalCenter; count: 5; dotSize: 4; gap: 2; value: c.hasBat ? c.bat.percentage : 0; litColor: c.hasBat && c.bat.percentage < 0.15 ? Theme.red : Theme.text }
          UiCaption { anchors.verticalCenter: parent.verticalCenter; text: c.hasBat ? Math.round(c.bat.percentage * 100) + "%" : ""; font.pixelSize: stage.cap }
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter; y: Math.round(parent.height * 0.47 - height / 2)
        spacing: Math.round(22 * c.k)
        Column {   // hero: the time, the date under it on one dotted rule
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Math.round(14 * c.k)
          UiNum {
            id: timeLine
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, c.timeFmt)
            font.pixelSize: Math.round(220 * c.k * Theme.scale)
          }
          UiDotLine { width: timeLine.width; anchors.horizontalCenter: parent.horizontalCenter }
          Item {
            width: timeLine.width; height: dateCap.height; anchors.horizontalCenter: parent.horizontalCenter
            UiCaption { id: dateCap; anchors.left: parent.left; text: c.dateFmt === "" ? "" : Qt.formatDate(clock.date, "dddd"); color: Theme.text; font.pixelSize: Math.round(18 * c.k * Theme.scale) }
            UiCaption { anchors.right: parent.right; text: c.dateFmt === "" ? "" : Qt.formatDate(clock.date, "d MMMM"); font.pixelSize: Math.round(18 * c.k * Theme.scale) }
          }
        }
        Column {   // the password: one dot per typed character on a track of faint dots; the caption under it says who / what went wrong
          id: pwCol
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 12
          transform: Translate { id: sh; x: 0 }
          SequentialAnimation { id: shakeAnim
            NumberAnimation { target: sh; property: "x"; to: -10; duration: 50 }
            NumberAnimation { target: sh; property: "x"; to: 10; duration: 80 }
            NumberAnimation { target: sh; property: "x"; to: 0; duration: 50 } }
          Connections { target: c; function onShakeChanged() { shakeAnim.restart() } }
          DotMeter {
            id: track
            onNChanged: c.track0 = n
            Component.onCompleted: c.track0 = n
            anchors.horizontalCenter: parent.horizontalCenter
            fit: stage.w; dotSize: Math.round(7 * c.k); gap: 7
            value: c.success ? c.fillV : c.busy ? Math.min(c.held, n) / n : Math.min(pw.text.length, n) / n
            litColor: c.error !== "" ? Theme.red : Theme.text
          }
          UiCaption {
            anchors.horizontalCenter: parent.horizontalCenter
            text: c.error !== "" ? c.error : c.success ? "Unlocked" : c.busy ? "Checking" : pw.text !== "" ? "Enter" : c.userName
            color: c.error !== "" ? Theme.red : pw.text !== "" ? Theme.text : Theme.dim
            font.pixelSize: stage.cap
          }
        }
      }

      Item {   // the player: one mono line + a dotted progress + the three glyphs, no plate
        id: media
        visible: !!c.player && Prefs.get("lock_media", true) !== false
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height - height - parent.height * 0.06)
        width: stage.w; height: 64
        Timer { running: media.visible && !!c.player && c.player.isPlaying; interval: 1000; repeat: true; onTriggered: c.player.positionChanged() }
        UiDotLine { width: parent.width }
        Row {
          anchors { left: parent.left; right: ctl.left; rightMargin: 12; top: parent.top; topMargin: 14 }
          spacing: 8
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.text; opacity: !!c.player && c.player.isPlaying ? 1 : 0.16 }
          UiCaption { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14; elide: Text.ElideRight; color: Theme.text; font.pixelSize: stage.cap
                      text: c.player ? [c.player.trackArtist, c.player.trackTitle || c.player.identity].filter(x => !!x).join(" - ") : "" }
        }
        Row {
          id: ctl
          anchors { right: parent.right; top: parent.top; topMargin: 8 }
          spacing: 6
          Repeater {
            model: [{ n: "skip-back", a: 0 }, { n: "play", a: 1 }, { n: "skip-forward", a: 2 }]
            MouseArea {
              required property var modelData
              width: 28; height: 28
              cursorShape: Qt.PointingHandCursor
              onClicked: { const pl = c.player; if (!pl) return; if (modelData.a === 0) pl.previous(); else if (modelData.a === 1) pl.togglePlaying(); else pl.next() }
              Icon { anchors.centerIn: parent; name: modelData.a === 1 && c.player && c.player.isPlaying ? "pause" : modelData.n; color: Theme.text; font.pixelSize: Math.round(Theme.barPx * 1.1) }
            }
          }
        }
        DotMeter {
          visible: !!c.player && c.player.lengthSupported && c.player.length > 0
          anchors { left: parent.left; bottom: parent.bottom }
          fit: parent.width; dotSize: 3; gap: 3
          value: c.player && c.player.length > 0 ? c.player.position / c.player.length : 0
        }
      }
    }
  }

  Loader {
    anchors.fill: parent; active: c.ui
    sourceComponent: lwts
  }
}
