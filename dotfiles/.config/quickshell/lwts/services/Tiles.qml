// Quick settings tile registry + layout (settings_spec 2.1-2.3): single owner of what a tile is and how tiles pack
// into the 4-slot row grid, so the real Quick Settings popup and the Settings constructor render the exact same thing.
// Storage (settings.toml, both lists plain string arrays - fully backward compatible with the old checkbox UI):
//   qs_tiles      ordered ids shown in Quick Settings (unchanged format: a plain id list, as before)
//   qs_widgets    ids from qs_tiles shown as a WIDGET (live tile under the text toggles in the launcher; 2 slots here);
//                 anything else is a quiet text toggle. Internally still called "wide". Basics (tray, net) are always text.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import qs.core

Singleton {
  id: root

  // ---- registry: id -> { icon, label(), status(): "" | live text, on(), act(), panel?, need()?, toggleless? } ----
  readonly property var all: Object.assign({}, baseAll, Modules.tiles)   // modules add their own tiles (services/Modules.qml)
  readonly property var baseAll: ({
    dark:     { icon: "circle-half", label: () => Session.dark ? "Dark" : "Light", on: () => Session.dark, act: () => Session.toggleDark() },
    game:     { icon: "feather", label: () => "Lite", on: () => Session.game, act: () => Session.toggleGame() },
    profile:  { icon: "lightning", label: () => "Power profile",
                status: () => ({ balanced: "Balanced", performance: "Performance", "power saver": "Power saver" })[Session.profile] || "Auto",
                on: () => Session.profile !== "auto", act: () => Session.cycleProfile() },
    mic:      { icon: "microphone", label: () => Audio.micMuted ? "Mic off" : "Mic", on: () => !Audio.micMuted, act: () => Audio.toggleMic(), panel: "audio" },
    mute:     { icon: Audio.icon, label: () => "Sound", on: () => !Audio.muted, act: () => Audio.toggleMute(), panel: "audio" },
    bt:       { icon: "bluetooth", label: () => "Bluetooth",
                status: () => { const d = Bluetooth.devices.values.find(d => d.connected); return d ? (d.name || d.address) : "" },
                on: () => !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled,
                act: () => Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled, panel: "bt", need: () => !!Bluetooth.defaultAdapter },
    wifi:     { icon: "wifi-high", label: () => "Wi-Fi",
                status: () => { const w = Networking.devices.values.find(d => d.type === DeviceType.Wifi);
                                 const n = w && w.networks ? w.networks.values.find(n => n.connected) : null; return n ? n.name : "" },
                on: () => Networking.wifiEnabled, act: () => Networking.wifiEnabled = !Networking.wifiEnabled,
                panel: "net", need: () => Networking.devices.values.some(d => d.type === DeviceType.Wifi) },
    sysmon:   { icon: "gauge", label: () => "System", on: () => false, act: () => {}, panel: "sysmon", toggleless: true },
    // the rest of the bar, so everything it shows is reachable from the keyboard (Enter opens the same drop the bar icon does)
    mixer:    { icon: "sliders-horizontal", label: () => "Mixer", status: () => Math.round(Audio.volume * 100) + "%",
                on: () => false, act: () => {}, panel: "audio", toggleless: true },
    net:      { icon: "network", label: () => "Network",
                status: () => { const d = Networking.devices.values.find(d => d.connected); return d ? (d.name || "") : "Offline" },
                on: () => Networking.devices.values.some(d => d.connected), act: () => {}, panel: "net", toggleless: true },
    layout:   { icon: "keyboard", label: () => "Layout", status: () => Keyboard.name, on: () => false, act: () => Keyboard.switchNext(),
                need: () => Keyboard.codes.length > 1 },
    tray:     { icon: "tray", label: () => "Tray", status: () => "", on: () => false, act: () => {},
                icons: () => SystemTray.items.values.map(i => i.icon), drill: true, toggleless: true, need: () => SystemTray.items.values.length > 0 },
    clock:    { icon: "calendar-blank", label: () => "Calendar", on: () => false, act: () => {}, panel: "clock", toggleless: true },
    notif:    { icon: "bell", label: () => "Notifications", on: () => false, act: () => {}, panel: "notif", toggleless: true },
    battery:  { icon: "battery-full", label: () => "Battery", status: () => Math.round(Session.bat.percentage * 100) + "%",
                on: () => false, act: () => {}, toggleless: true, need: () => !!Session.bat && Session.bat.isLaptopBattery },
    dnd:      { icon: "bell-slash", label: () => "Do not disturb", on: () => Notifs.dnd, act: () => Notifs.toggleDnd() },
    flight:   { icon: "airplane", label: () => "Flight mode", on: () => root.flightOn,
                act: () => { root.flightOn = !root.flightOn; Quickshell.execDetached(["rfkill", root.flightOn ? "block" : "unblock", "all"]) } },
  })

  // ---- flight mode: rfkill has no change signal, so this is a one-shot check (on load + after each toggle) ----
  property bool flightOn: false
  Process {
    id: rfkillCheck
    command: ["rfkill", "-no", "SOFT"]
    stdout: StdioCollector { onStreamFinished: { const lines = this.text.trim().split("\n").filter(l => l); root.flightOn = lines.length > 0 && lines.every(l => l.trim() === "blocked") } }
  }
  Component.onCompleted: rfkillCheck.running = true

  // ---- active list + wide set (storage) -----------------------------------------------
  readonly property var defaultTiles: ["dark", "night", "game", "caffeine", "profile", "mic", "bt", "wifi", "sysmon", "ai"]
  readonly property var defaultWide: []
  // launcher v2 (user 2026-11-13): every item is a TILE; only a switch (on/off: no `toggleless`) may also be a quiet text chip.
  // Bar duplicates (System, Mixer, Network, Calendar, Notifications, Layout, Sound) and unpicked items are not offered in the bank.
  readonly property var offered: ["dark", "night", "game", "dnd", "caffeine", "wifi", "bt", "vpn", "powertimer", "clip", "notes", "tray",
                                  "shot", "picker", "ocr", "timer", "batteries", "focus", "sleep", "stream", "speed"]   // + own widgets x_*
  function tileOnly(id) { const t = all[id]; return !!t && !!t.toggleless && !t.drill }   // no on/off = no text form (the tray is its own row)
  function textOnly(id) { const t = all[id]; return !!t && !!t.drill }                       // the tray icons line
  // Tiles are laid out in the user's own rows (qs_tile_rows = ["speed,picker,focus", "x_weather,ocr"]; Settings -> Layout: drop a tile
  // on another = same row, between rows = a new row). In a row the tiles share the width; an "icon" tile (qs_tile_sizes "id:icon")
  // is a square that widens at most to 1.5 squares, the others take the rest. A tile alone in its row is simply wide.
  // Tiles not placed yet go two per row. A row that cannot hold its tiles (min 88 px a normal tile) wraps.
  readonly property var sizes: { const o = {}; for (const s of Prefs.get("qs_tile_sizes", [])) { const p = String(s).split(":"); if (p[1] === "icon") o[p[0]] = "icon" } return o }
  function sizeOf(id) { return sizes[id] || "default" }
  function cycleSize(id) {
    const l = Prefs.get("qs_tile_sizes", []).filter(s => String(s).split(":")[0] !== id);
    Prefs.set("qs_tile_sizes", sizeOf(id) === "icon" ? l : l.concat([id + ":icon"]));
  }
  readonly property var tileRowsPref: Prefs.get("qs_tile_rows", []).map(r => String(r).split(",").filter(x => x))
  function setTileRows(rows) { Prefs.set("qs_tile_rows", rows.filter(r => r.length).map(r => r.join(","))) }
  function tileRowIds(ids, W, H) {   // the rows as they show: user rows (only ids shown now), new ids two per row, too-full rows wrapped
    W = W || 400; H = H || 38;
    const rows = tileRowsPref.map(r => r.filter(id => ids.includes(id))).filter(r => r.length);
    const placed = flatten(rows), rest = ids.filter(id => !placed.includes(id));
    for (let k = 0; k < rest.length; k += 2) rows.push(rest.slice(k, k + 2));
    const out = [];
    for (const r of rows) {
      let cur = [], used = 0;
      for (const id of r) { const m = sizeOf(id) === "icon" ? H : 88; if (cur.length && used + 6 + m > W) { out.push(cur); cur = []; used = 0 } used += (cur.length ? 6 : 0) + m; cur.push(id) }
      if (cur.length) out.push(cur);
    }
    return out;
  }
  function tileRows(ids, W, H, g) {   // -> [{ items: [{ id, w }], spacing }]
    return tileRowIds(ids, W, H).map(r => {
      const icons = r.filter(id => sizeOf(id) === "icon"), others = r.length - icons.length;
      const free = W - g * (r.length - 1);
      if (!others) {   // only icons: squares, spread over the line
        const spacing = r.length > 1 ? (W - H * r.length) / (r.length - 1) : g;
        return { items: r.map(id => ({ id, w: Math.floor(H) })), spacing: Math.max(g, spacing) };
      }
      const iw = Math.min(H * 1.5, Math.max(H, (free - others * 88) / Math.max(1, icons.length)));
      const ow = (free - iw * icons.length) / others;
      return { items: r.map(id => ({ id, w: Math.floor(sizeOf(id) === "icon" ? (others ? Math.min(iw, H * 1.5) : H) : ow) })), spacing: g };
    });
  }
  // a tile's face: status line, an optional short hero number (dot-matrix, right) and the alert flag. A def may give face();
  // otherwise status() / alert() are used as they are.
  function face(id) {
    const t = all[id]; if (!t) return { status: "", hero: "", alert: false, icon: "", info: false };
    const f = t.face ? t.face() : null;
    return { status: f ? f.status || "" : (t.status ? t.status() : ""), hero: f ? f.hero || "" : "", alert: f ? !!f.alert : (t.alert ? !!t.alert() : false),
             icon: (f && f.icon) || t.icon, info: !!t.toggleless };   // info = live data, never "off": drawn bright, not dimmed
  }
  function packRows(ids, W, H) { return tileRowIds(ids, W, H) }   // the keyboard rows = the picture
  readonly property var activeIds: Prefs.get("qs_tiles", defaultTiles).filter(id => all[id] && (!all[id].need || all[id].need()))
  readonly property var wideIds: Prefs.get("qs_widgets", defaultWide).filter(id => !textOnly(id)).concat(Prefs.get("qs_tiles", defaultTiles).filter(id => tileOnly(id)))
  readonly property var active: activeIds.map(id => ({ id, wide: wideIds.includes(id) }))
  readonly property var bank: Object.keys(all).filter(id => (offered.includes(id) || id.startsWith("x_")) && !activeIds.includes(id) && (!all[id].need || all[id].need()))

  // ---- layout (rows) -----------------------------------------------------------------------------------------
  // `qs_rows` = ["wifi,profile", "bt,mic,night,dnd"]: the user's own rows (4 slots each, wide = 2). Empty = packed automatically
  // (pack). The popup, the constructor and the keyboard all read `layoutRows`, so there is one layout for everybody.
  readonly property var rowsPref: Prefs.get("qs_rows", [])
  readonly property var layoutRows: buildRows()
  function flatten(rows) { return [].concat(...rows) }   // this QML engine has no Array.flat
  function slotsOf(id, wide) { return (wide || wideIds).includes(id) ? 2 : 1 }
  function normalize(rows, wide) {   // drop unknown / duplicate ids, split rows that do not fit 4 slots
    const out = [], seen = {};
    for (const r of rows) {
      let cur = [], used = 0;
      for (const id of r) {
        if (!all[id] || seen[id]) continue; seen[id] = true;
        const w = slotsOf(id, wide);
        if (used + w > 4 && cur.length) { out.push(cur); cur = []; used = 0 }
        cur.push(id); used += w;
      }
      if (cur.length) out.push(cur);
    }
    return out;
  }
  function buildRows() {
    const ids = activeIds;
    if (!rowsPref.length) return pack(active);
    const rows = normalize(rowsPref.map(r => String(r).split(",").filter(x => x && ids.includes(x))), wideIds);
    const placed = flatten(rows), rest = ids.filter(id => !placed.includes(id));
    return normalize(rows.concat(rest.length ? [rest] : []), wideIds).map(r => r.map(id => ({ id, wide: wideIds.includes(id), slots: slotsOf(id) })));
  }
  function idRows() { return layoutRows.map(r => r.map(t => t.id)) }
  function commitRows(rows, wide) {   // rows: arrays of ids
    const n = normalize(rows, wide || wideIds);
    Prefs.setMany({ qs_tiles: flatten(n), qs_rows: n.map(r => r.join(",")), qs_widgets: wide || wideIds });
  }
  function setActiveIds(ids) { Prefs.setMany({ qs_tiles: ids, qs_rows: [] }) }
  function toggleWide(id) { if (textOnly(id) || tileOnly(id)) return; const w = wideIds.slice(), i = w.indexOf(id); if (i >= 0) w.splice(i, 1); else w.push(id); commitRows(idRows(), w) }
  // Settings -> Features -> Toggles / Info: one item's look. "off" | "text" | "widget". Works on the raw prefs, so ids that are
  // hidden right now (module off, no hardware) keep their place instead of being dropped like commitRows would.
  function lookOf(id) { return Prefs.get("qs_tiles", defaultTiles).includes(id) ? (wideIds.includes(id) ? "widget" : "text") : "off" }
  function setLook(id, v) {
    let rows = Prefs.get("qs_rows", []).map(r => String(r).split(",").filter(x => x));
    if (!rows.length) rows = [Prefs.get("qs_tiles", defaultTiles).slice()];
    const present = flatten(rows).includes(id);
    if (v === "off") rows = rows.map(r => r.filter(x => x !== id));
    else if (!present) rows[rows.length - 1].push(id);
    rows = rows.filter(r => r.length);
    const w = Prefs.get("qs_widgets", []).filter(x => x !== id).concat(v === "widget" && !textOnly(id) ? [id] : []);
    Prefs.setMany({ qs_tiles: flatten(rows), qs_rows: rows.map(r => r.join(",")), qs_widgets: w });
  }
  function setOrder(ids) {   // Layout constructor: the visible items in this order; hidden ones (module off, no hardware) keep riding at the end
    const hidden = Prefs.get("qs_tiles", defaultTiles).filter(x => !ids.includes(x) && !(all[x] && (!all[x].need || all[x].need())));
    const o = ids.concat(hidden);
    Prefs.setMany({ qs_tiles: o, qs_rows: [o.join(",")] });
  }
  function addTile(id) {
    if (activeIds.includes(id)) return;
    const rows = idRows(), last = rows[rows.length - 1];
    if (last && last.reduce((a, x) => a + slotsOf(x), 0) + slotsOf(id) <= 4) last.push(id); else rows.push([id]);
    commitRows(rows);
  }
  function removeTile(id) { commitRows(idRows().map(r => r.filter(x => x !== id))) }
  function moveTile(from, to) {   // keyboard: move in the flat order, the rows keep their lengths
    const rows = idRows(), lens = rows.map(r => r.length), flat = flatten(rows), [id] = flat.splice(from, 1);
    flat.splice(Math.max(0, Math.min(flat.length, to)), 0, id);
    const out = []; let i = 0; for (const n of lens) { out.push(flat.slice(i, i + n)); i += n }
    commitRows(out);
  }
  // mouse: put `id` into row `row` before column `col`, or into a new row inserted at `row` (newRow); id may come from the bank
  function placeTile(id, row, col, newRow) {
    const rows = idRows(); let target = row;
    for (let r = 0; r < rows.length; r++) { const i = rows[r].indexOf(id); if (i >= 0) { rows[r].splice(i, 1); if (!rows[r].length && r < target) target-- } }
    const clean = rows.filter(r => r.length);
    if (newRow) clean.splice(Math.max(0, Math.min(clean.length, target)), 0, [id]);
    else if (clean.length === 0) clean.push([id]);
    else { const r = clean[Math.max(0, Math.min(clean.length - 1, target))]; r.splice(Math.max(0, Math.min(r.length, col)), 0, id) }
    commitRows(clean);
  }

  // ---- smart flex grid packing (settings_spec 2.2): 4 slots/row, wide = 2, never force-shrinks a wide tile ----
  // Returns rows of { id, wide, slots }; a row that does not fill all 4 slots lets its tiles stretch (fillWidth)
  // in the renderer instead of leaving a hole.
  function pack(list) {
    const rows = []; let row = [], used = 0;
    for (const t of list) {
      const w = t.wide ? 2 : 1;
      if (used + w > 4 && row.length) { rows.push(row); row = []; used = 0 }
      row.push({ id: t.id, wide: t.wide, slots: w }); used += w;
      if (used === 4) { rows.push(row); row = []; used = 0 }
    }
    if (row.length) rows.push(row);
    return rows;
  }

  // ---- presets (settings_spec 2.3) -----------------------------------------------------
  // Factory presets use only tiles that exist (`all` above); a few spec items have no backend yet
  // (screen-recording / gamepad status, GPU-OC VRR profile, hotspot) and are left out rather than faked -
  // "Sound"/"Flight mode"/"Do not disturb"/"Water" stand in for them where the intent matches closely enough.
  readonly property var factoryPresets: [
    { id: "balanced", label: "Basic", tiles: [
        { id: "wifi", wide: true }, { id: "profile", wide: true },
        { id: "bt", wide: false }, { id: "mic", wide: false }, { id: "night", wide: false }, { id: "dnd", wide: false },
        { id: "dark", wide: false }, { id: "caffeine", wide: false }, { id: "ai", wide: false },
      ] },
    { id: "gaming", label: "Gaming / Max FPS", tiles: [
        { id: "game", wide: true }, { id: "profile", wide: true },
        { id: "mic", wide: false }, { id: "dnd", wide: false }, { id: "mute", wide: false }, { id: "water", wide: false },
      ] },
    { id: "night_health", label: "Night workflow & health", tiles: [
        { id: "night", wide: true }, { id: "water", wide: true },
        { id: "dark", wide: false }, { id: "caffeine", wide: false }, { id: "dnd", wide: false }, { id: "ai", wide: false },
      ] },
    { id: "mobile", label: "Laptop", tiles: [
        { id: "profile", wide: true }, { id: "wifi", wide: true },
        { id: "flight", wide: false }, { id: "bt", wide: false }, { id: "game", wide: false }, { id: "dnd", wide: false },
      ] },
    { id: "stealth", label: "Stealth / minimal", tiles: [
        { id: "wifi", wide: false }, { id: "mute", wide: false }, { id: "dnd", wide: false }, { id: "night", wide: false },
      ] },
  ]
  // Custom presets are nested objects (id/label/tiles), which settings.toml's flat `key = value` lines
  // cannot hold (no tables/JSON strings there - see daynight.lua) - a separate JSON file instead, same
  // pattern as ~/.local/state/daily-quests.json.
  property var customPresets: []
  readonly property var presets: factoryPresets.concat(customPresets)
  function writeCustomPresets(list) { customPresets = list; presetsFile.setText(JSON.stringify(list)) }
  FileView {
    id: presetsFile
    path: Quickshell.env("HOME") + "/.local/state/qs-presets.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.customPresets = JSON.parse(text()) } catch (e) { root.customPresets = [] } }
  }

  function applyPreset(id) {
    const p = presets.find(p => p.id === id); if (!p) return;
    Prefs.setMany({ qs_tiles: p.tiles.map(t => t.id), qs_rows: [], qs_widgets: p.tiles.filter(t => t.wide).map(t => t.id) });
  }
  function saveCustomPreset(name) {
    const id = "custom_" + Date.now();
    const tiles = activeIds.map(id => ({ id, wide: wideIds.includes(id) }));
    writeCustomPresets(customPresets.concat([{ id, label: name, tiles }]));
    return id;
  }
  function renameCustomPreset(id, name) { writeCustomPresets(customPresets.map(p => p.id === id ? Object.assign({}, p, { label: name }) : p)) }
  function overwriteCustomPreset(id) {
    const tiles = activeIds.map(x => ({ id: x, wide: wideIds.includes(x) }));
    writeCustomPresets(customPresets.map(p => p.id === id ? Object.assign({}, p, { tiles }) : p));
  }
  function deleteCustomPreset(id) { writeCustomPresets(customPresets.filter(p => p.id !== id)) }
}
