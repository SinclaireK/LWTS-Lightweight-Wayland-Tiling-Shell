// Notification server (freedesktop): the one owner of notifications. Pop-ups and the centre read `list` / `popups`.
// Do not disturb (Settings -> Shell) and Lite mode keep pop-ups away; everything still lands in the centre.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.core

Singleton {
  id: root
  // settings_spec 7.4: "system toast" = sent via the bare `notify-send` CLI (no -a appname) by our own shell
  // scripts (power timer, night light, ...) rather than a real app with its own desktop entry - a heuristic,
  // not exhaustive (see settings_gaps.md).
  function lifeOf(n) { return n.expireTimeout > 0 ? n.expireTimeout : n.urgency === NotificationUrgency.Critical ? 0 : Number(Prefs.get("notif_timeout", 5000)) }
  function isSystemToast(n) { return ["notify-send", "niri", "Screenshot"].includes(n.appName || "") }   // niri: "Screenshot captured"; Screenshot: our own tool (saved/GIF saved + Open/Folder/Copy/Delete), gone with its pop-up
  // settings_spec 7.4: keep only the newest N (preset 30/50/100) - trims the tracked list itself, not just the view
  readonly property var list: server.trackedNotifications.values.filter(n => Prefs.get("notif_keep_system", false) || !isSystemToast(n))
                                 .slice().reverse().slice(0, Prefs.get("notif_limit", 50))
  property var popups: []          // shown as drops under the dot, newest first
  property int unread: 0
  readonly property int urgency: list.length ? Math.max(...list.slice(0, Math.max(1, unread)).map(n => n.urgency)) : 0
  // settings_spec 7.1: 3 modes, one key `notif_mode`. Do not disturb (Quick-settings tile, Notification centre row)
  // = any mode but "both"; its toggle flips "both" <-> "dot" ("silence" is reachable only from Settings).
  // Old bool `dnd` is read only while `notif_mode` was never saved (it used to be a second key the mode ignored: D74).
  readonly property string mode: Prefs.get("notif_mode", Prefs.get("dnd", false) ? "dot" : "both")
  readonly property bool dnd: mode !== "both"
  function toggleDnd() { Prefs.set("notif_mode", dnd ? "both" : "dot") }
  readonly property bool silence: mode === "silence"
  readonly property bool quiet: mode !== "both" || Theme.playing || (Prefs.get("notif_quiet_in_game", true) && Session.game)

  // per-app mute (the card's bell-slash button): a muted app's notifications are dropped on arrival; Notification centre lists them to unmute
  readonly property var muted: Prefs.get("notif_muted", [])
  function mute(n) { const a = n.appName || ""; if (a && !muted.includes(a)) Prefs.set("notif_muted", muted.concat([a])); dismiss(n) }
  function unmute(app) { Prefs.set("notif_muted", muted.filter(x => x !== app)) }

  // arrival time per notification id (a Notification object takes no extra properties) and the pop-up expiry timers (hover holds them)
  property var stamps: ({})
  property var timers: ({})
  function timeOf(n) { const t = n ? stamps[n.id] : 0; return t ? Qt.formatTime(new Date(t), "HH:mm") : "" }
  function hold(n, on) { const t = n ? timers[n.id] : null; if (t) t.running = !on }   // hover: the pop-up waits, leaving restarts the full time
  function seen() { unread = 0 }
  function dismiss(n) { popups = popups.filter(p => p !== n); n.dismiss() }
  function hide(n) { popups = popups.filter(p => p !== n) }   // pop-up gone, stays in the centre
  function clear() { for (const n of list.slice()) n.dismiss(); popups = []; unread = 0 }
  // does a click have anywhere to go: a default action, any action, or an app to focus (otherwise the card has no OPEN button and a click does nothing)
  function openable(n) { return !!n && (n.actions.length > 0 || (!!n.desktopEntry && !!DesktopEntries.byId(n.desktopEntry))) }
  function open(n) {   // default action, or focus the app that sent it
    const a = n.actions.find(x => x.identifier === "default") || n.actions[0];
    if (a) a.invoke(); else if (n.desktopEntry) { const e = DesktopEntries.byId(n.desktopEntry); if (e) e.execute() }
    dismiss(n);
  }

  NotificationServer {
    id: server
    keepOnReload: true
    bodySupported: true
    actionsSupported: true
    imageSupported: true
    persistenceSupported: true
    onNotification: n => {
      n.tracked = true;
      if (root.muted.includes(n.appName || "")) { n.dismiss(); return }
      // the sender can close/replace it over D-Bus: drop it from `popups` at once, else the Repeater keeps a dead object and the
      // next `popups = [...]` segfaults in QtQmlModels (coredumps 2026-10-27 13:03, 21:07, 2026-10-28 15:36)
      n.closed.connect(() => root.hide(n));
      root.stamps[n.id] = Date.now();
      // a system toast is not shown in the centre (see `list`): it must not light the dot, and it is dropped with its pop-up
      // instead of piling up hidden in the tracked list
      const sys = root.isSystemToast(n) && !Prefs.get("notif_keep_system", false);
      if (!sys) root.unread++;
      const showPopup = !root.silence && (!root.quiet || n.urgency === NotificationUrgency.Critical);
      if (!showPopup && sys) n.dismiss();
      if (showPopup) {
        root.popups = [n].concat(root.popups).slice(0, 2);
        const snd = Prefs.get("notif_sound", "off");   // settings_spec 4.5: off | all | critical (system toasts never beep)
        if (snd !== "off" && !root.isSystemToast(n) && (snd === "all" || n.urgency === NotificationUrgency.Critical))
          Sounds.play(n.urgency === NotificationUrgency.Critical ? "dialog-warning" : "message-new-instant");
        const t = root.lifeOf(n);
        if (t > 0) {
          const tm = Qt.createQmlObject('import QtQuick; Timer { running: true; interval: ' + t + ' }', root);
          root.timers[n.id] = tm;
          tm.triggered.connect(() => { delete root.timers[n.id]; tm.destroy(); if (sys) root.dismiss(n); else root.hide(n) });
        }
      }
      const over = server.trackedNotifications.values.length - Number(Prefs.get("notif_limit", 50));   // settings_spec 7.4: actually free the oldest, not just hide them
      if (over > 0) server.trackedNotifications.values.slice(0, over).forEach(x => x.dismiss());
    }
  }
}
