// Media (bar: right click on the track): cover, title, seek bar, ⏮ ⏯ ⏭, shuffle / repeat and player volume when the
// player supports them, player switch when several. Keys: Space/Enter pause, ← → seek 5 s, Ctrl+← → track,
// ↑ ↓ volume, Tab next player, Esc close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.core
import qs.services
import qs.widgets

ColumnLayout {
  id: p
  spacing: 8
  focus: true
  readonly property bool wantsKeys: true
  signal closeMe()
  readonly property var players: Mpris.players.values.filter(pl => !(pl.dbusName || "").includes("playerctld"))
  property int pick: -1   // chosen player index; -1 = the playing one (as in the bar)
  readonly property var player: pick >= 0 && pick < players.length ? players[pick]
                                : MediaPick.player
  // Chromium players (Helium, web apps) report a volume but ignore changes: drive their PipeWire stream instead
  readonly property bool chromium: !!player && (player.dbusName || "").includes("chromium")
  // .audio and .properties exist only on a bound node: bind every app stream first, then pick by application name
  readonly property var appNodes: !chromium ? [] : Pipewire.nodes.values.filter(n => n.isStream && n.isSink)
  PwObjectTracker { objects: p.appNodes }
  readonly property var streams: appNodes.filter(n => n.audio && n.properties["application.name"] === player.identity)
  readonly property var stream: streams[0] || null
  readonly property bool hasVol: chromium ? !!stream && !!stream.audio : !!player && player.volumeSupported
  readonly property real volume: chromium ? (stream && stream.audio ? stream.audio.volume : 0) : (player ? player.volume : 0)
  function setVol(v) { v = Math.max(0, Math.min(1, v)); if (chromium) { streams.forEach(n => { if (n.audio) n.audio.volume = v }) } else if (player) player.volume = v }

  function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
  function seek(d) { if (player && player.canSeek) player.position = Math.max(0, Math.min(player.length, player.position + d)) }
  function vol(d) { if (hasVol) setVol(volume + d) }
  function nextPlayer() { if (players.length > 1) pick = (players.indexOf(player) + 1) % players.length }
  function cycleLoop() {
    player.loopState = player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                     : player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
  }

  Keys.onPressed: e => {
    if (!player) { if (e.key === Qt.Key_Escape) p.closeMe(); return }
    const ctrl = e.modifiers & Qt.ControlModifier
    if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) player.togglePlaying()
    else if (e.key === Qt.Key_Left) ctrl ? player.previous() : p.seek(-5)
    else if (e.key === Qt.Key_Right) ctrl ? player.next() : p.seek(5)
    else if (e.key === Qt.Key_Up) p.vol(0.05)
    else if (e.key === Qt.Key_Down) p.vol(-0.05)
    else if (e.key === Qt.Key_Tab) p.nextPlayer()
    else if (e.key === Qt.Key_Escape) p.closeMe()
    else return
    e.accepted = true
  }

  // MPRIS sends position only on seek: refresh it while the panel is open and playing
  Timer { running: !!p.player && p.player.isPlaying; interval: 1000; repeat: true; onTriggered: p.player.positionChanged() }

  component Btn: UiIconButton {}   // the shared icon button (widgets/UiIconButton.qml)

  UiCaption { visible: !p.player; text: "Nothing playing"; Layout.margins: 4 }

  RowLayout {   // hero: where the track is, in dots; the player on the right (several = click / Tab switches)
    visible: !!p.player
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 8
    UiNum { text: p.player ? p.fmt(p.player.position) : ""; size: Math.round(34 * Theme.scale) }
    UiCaption { visible: !!p.player && p.player.lengthSupported && p.player.length > 0; text: "/ " + (p.player ? p.fmt(p.player.length) : ""); Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 6 }
    Item { Layout.fillWidth: true }
    MouseArea {
      implicitWidth: who.implicitWidth + 16; implicitHeight: who.implicitHeight + 8; Layout.alignment: Qt.AlignTop
      enabled: p.players.length > 1; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: p.nextPlayer()
      Row {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.text; opacity: p.player && p.player.isPlaying ? 1 : 0.16 }
        UiCaption { id: who; text: p.player ? p.player.identity : ""; color: Theme.text }
        UiCaption { visible: p.players.length > 1; text: (p.players.indexOf(p.player) + 1) + "/" + p.players.length }
      }
    }
  }
  Slider {   // the track: dots, drag or click to seek
    visible: !!p.player && p.player.lengthSupported && p.player.length > 0
    Layout.fillWidth: true; enabled: p.player && p.player.canSeek
    value: p.player && p.player.length > 0 ? p.player.position / p.player.length : 0
    onMoved: v => { if (p.player && p.player.canSeek) p.player.position = v * p.player.length }
  }

  UiDotLine { visible: !!p.player; Layout.fillWidth: true; Layout.topMargin: 2 }

  RowLayout {   // what plays: cover, title, artist (mono caps)
    visible: !!p.player
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 12
    Rectangle {
      Layout.preferredWidth: 48; Layout.preferredHeight: 48
      radius: Theme.radiusInner; color: "transparent"; border.width: 1; border.color: Theme.edge; clip: true
      Icon { anchors.centerIn: parent; name: "music-note"; color: Theme.dim; visible: cover.status !== Image.Ready; font.pixelSize: 20 }
      Image { id: cover; anchors.fill: parent; anchors.margins: 1; source: p.player ? p.player.trackArtUrl : ""
              fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(96, 96) }
      MouseArea { anchors.fill: parent; onWheel: w => p.vol(w.angleDelta.y > 0 ? 0.05 : -0.05) }
    }
    ColumnLayout {
      Layout.fillWidth: true; spacing: 4
      Text { Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.text
             text: p.player ? (p.player.trackTitle || p.player.identity) : ""
             font.family: Theme.font; font.pixelSize: Math.round(14 * Theme.scale) }
      UiCaption { Layout.fillWidth: true; elide: Text.ElideRight; visible: text !== ""
                  text: p.player ? [p.player.trackArtist, p.player.trackAlbum].filter(x => x).join(" - ") : "" }
    }
  }

  RowLayout {   // controls
    visible: !!p.player
    Layout.fillWidth: true; spacing: 4
    Btn { icon: "shuffle"; visible: p.player && p.player.shuffleSupported; on: p.player && p.player.shuffle
          onClicked: p.player.shuffle = !p.player.shuffle }
    Item { Layout.fillWidth: true }
    Btn { icon: "skip-back"; enabled: p.player && p.player.canGoPrevious; onClicked: p.player.previous() }
    Btn { icon: p.player && p.player.isPlaying ? "pause" : "play"; big: true; onClicked: p.player.togglePlaying() }
    Btn { icon: "skip-forward"; enabled: p.player && p.player.canGoNext; onClicked: p.player.next() }
    Item { Layout.fillWidth: true }
    Btn { icon: p.player && p.player.loopState === MprisLoopState.Track ? "repeat-once" : "repeat"
          visible: p.player && p.player.loopSupported; on: p.player && p.player.loopState !== MprisLoopState.None
          onClicked: p.cycleLoop() }
  }

  UiDotLine { visible: p.hasVol; Layout.fillWidth: true; Layout.topMargin: 2 }
  RowLayout {   // the player's own volume, if it has one: key | track | percent (fixed columns, like Audio)
    visible: p.hasVol
    Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 10
    UiCaption { text: "Volume"; Layout.preferredWidth: 56 }
    Slider { Layout.fillWidth: true; value: p.volume; onMoved: v => p.setVol(v) }
    UiCaption { text: Math.round(p.volume * 100) + "%"; color: Theme.text; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
  }
}
