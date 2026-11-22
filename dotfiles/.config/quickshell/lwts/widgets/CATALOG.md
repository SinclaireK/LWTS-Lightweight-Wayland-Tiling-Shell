# LWTS widget catalog (read this BEFORE building any UI)

Style: Nothing look, LWTS structure. Colours only from `Theme.*` (palettes `nothing-dark` / `nothing-light` by default), never hex.
Fonts: UI `Theme.font` (Geist), labels/buttons/captions `Theme.label` (Geist Mono, CAPS), numerals only `Theme.dot` (Ndot57Caps community copy, local only, no licence; free fallback "LWTS Dot" = Doto static, >= 13 px).
Colour: monochrome; "on" = `Theme.accent` (white on dark / black on light) with `Theme.onAccent` contents; red = `Theme.red`, alerts only.
Surfaces: glass (transparency = glass, user returned it 2026-11-09; was solid in the first Nothing pass), NO grey plates: controls/tiles/rows are 1 px outlines (`Theme.edge` = text 24%), list groups = hairlines (`Theme.line`); fill only on hover (`Theme.fillHover`) or a solid accent plate when on.
Brand reference (community, from Nothing Brand Guidelines): https://nothing.wiki/nothing/brand_reference - black #000, white #fff, Window Grey #B1B3B3, N-Grey #F2F2EE, red #D71920 (OS) / #C8102E, yellow #FFC700, blue #002F6C; mono + dot text tracking 0; headlines sentence case, tight (-2%), never caps; no colour fills, shadows or gradients on graphics; dot-matrix font = names/numerals only.
NOT Material/Google: no filled circles, no pill buttons, no Material icons, no filled plates for "on". ON = white outline + the red dot (tiles) / red knob (toggles). Separators = dotted rules (`UiDotLine`).
Icons: Phosphor Light (`Theme.icons`), Fill only for an active state.
Text: bar / placeholders / statuses / captions / buttons = `Theme.label` CAPS; body = `Theme.font`.
Motion: crisp, no overshoot (`Motion.dropCurve`); dots switch on/off, never half-lit.
Shape: controls are 6 px rectangles via `Theme.radiusCtl` (0 on the square preset), no pills; plates `Theme.radius`, cards `Theme.radiusCard`, rows/fields `Theme.radiusInner`.

RULE: a toggle, button, chip, segment, slider, meter, caption, title or big number is ALWAYS one of the widgets below.
Missing one? Add it to `widgets/` as `Ui<Name>.qml`, add it here, then use it. No inline copies, no local `component` look-alikes.
Changed a widget's API or look? Update this file in the same step. Import: `import qs.widgets` (files in widgets/ need none).

## Controls
- `UiToggle` - On/Off switch (6 px track + sliding square-ish knob). `on`, `focusedChip` (keys), `onClicked`. 32x24 hit, 16 px track.
  `UiToggle { on: Prefs.get("x", false); onClicked: Prefs.set("x", !on) }`
- `UiButton` - button / chip, mono caps text, accent plate when `on`. `text`, `on`, `focusedChip`, `flat` (no fill at rest), `padX` (14). 22 px high.
  `UiButton { text: "Apply"; onClicked: doIt() }`
- `UiSegmented` - the whole segmented control: outlined track + one accent pill gliding to the pick (Settings look). `options` [[id,"Label"],..], `current`, `picked(id)`. Use for every 2-5 way switch (Settings still has its own copy of this inside `choice`; migrate when touched).
  `UiSegmented { options: [["a","One"],["b","Two"]]; current: x; onPicked: id => x = id }`
- `UiSeg` - one segment of a joined control (owner draws the container + sliding accent pill, see SettingsNew "choice"). `text`, `on`, `focusedChip`.
- `Slider` - dot track (accent dots), thumb on hover/drag. `value` 0..1, signal `moved(v)`; wheel steps 5%.
  `Slider { value: Audio.volume; onMoved: v => Audio.setVolume(v) }`
- `KnoblessSlider` - Settings slider, dots, value text on the right. `value`, `steps` or `from/to/stepSize`, `unit`/`format`, `moved(v)`, `stepBy(d)`.
- `ListRow` - list row: icon, title, optional sub-line, trail. 28 px (38 with sub). `act` / `alt` signals. Drop panels use `led: true`: lit LED dot = current / connected (no icon, no tint plate), mono caps trail, `meter` 0..1 = 5-dot battery before the trail.
- `Tile` - quick-settings tile (compact icon / wide icon+name+status); `on` = solid accent plate, status in mono caps, countdown in Doto.
- `UiIconButton` - icon-only button. `icon`, `on`, `big` (40 px accent plate: main action), `size` (30).
  `UiIconButton { icon: "play"; big: true; onClicked: Media.toggle() }`

## Display
- `UiFoldRow` - drop-panel fold row: mono caps `text`, dim `value`, caret; `open`, `focused`, `act()`; the owner flips `open` (one block open at a time, see `concepts/panel-style.md`).
  `UiFoldRow { text: "Devices"; open: p.devs; onAct: p.devs = !p.devs }`
- `UiCycleRow` - pick one of N in one line (drop panels: audio output / input): caption, glyph, name, pager (dots <= 6, "3/9" beyond), chevron. `count`, `index`, `step(d)`; click / Enter / → next, right click / ← previous, wheel.
  `UiCycleRow { caption: "Output"; icon: "monitor"; text: name; count: n; index: i; onStep: d => pick(d) }`
- `UiChip` - quiet text switch (launcher): mono caps label, bright when `on`, dim when off; no box. `text`, `on`, `focusedChip`, `hint` (Alt letter shown while Alt held), `act()`, `details()` (right click).
- `UiKvRow` - quiet key/value row: dim `key` column, then `value` text OR a dot track (`track` 0..1, `trail`, `moved(v)`) OR custom children; `led`, `off` (muted: dim track + red MUTE), `timed` (dot-matrix numerals), `focusedRow`, `hint`, `act()`, `details()`.
- `UiHintBadge` - Alt-letter badge (accent square, same look as UiKvRow hint); `letter` ("" = hidden). Used by the POWER button and PowerList rows.
- `UiDotLine` - dotted 1 px rule (Nothing separator). `color`, `strength`; set `width`.
- `DotMeter` - row of dots for a level. `value` 0..1, `count` (20) or `fit: width` (fills a width), `dotSize` (4), `gap` (3),
  `litColor` (Theme.text), `hot` threshold + `hotColor` (accent). Used by sliders, SysMon, OSD.
- `DotGraph` - history graph in dot-matrix columns (newest right). `series` / `series2` (0..1 arrays), `pitch` (6), `dot` (4), `hot` (0.9 = red). Fills its size.
  `DotGraph { Layout.fillWidth: true; Layout.fillHeight: true; series: Tasks.series("cpu") }`
- `UiNavItem` - rail item: `label`, `glyph`, `on` (outline), `link` (trailing arrow), `compact` (icon only), `clicked`. `UiSortHead` - sortable column header: `label`, `total`, `active` (red dot), `clicked`.
- `UiTable` - sortable table: header (`UiSortHead`) + scrolling rows, section rows `{hdr, count}`, picked row = outline. `columns` [{k,label,w,right,meter,mono,total,fmt,color,dot}], `rows`, `rowKey`, `sel`, `sortBy`, `sortRequested(key)`, `rowClicked(row)`, `pick(d)`.
- `UiComposeBar` - dotted bar split into parts (memory composition): `segments` [{v, a(opacity)}], `dotSize`, `gap`. Fills its width.
- `UiKindIcon` - app kind as a 7x7 dot glyph: `kind` (browser terminal game chat video music editor code files system office graphics network ai other), `dot`, `gap`, `color`, `faint`. Kind from `Kinds.ofProcess(name)` / `Kinds.ofEntry(entry)` (services/Kinds.qml; glyphs + rules in widgets/kinds.js).
- `UiNum` - Doto numerals (clock, levels). Set `font.pixelSize` (>= 13).
- `UiTitle` - headline: UI font Thin, 24 px: page / window titles.
- `UiCaption` - mono caps caption, 10 px, dim: group headers, section labels.
- `Icon` - Phosphor glyph. `name`, `fill`, `color`.
- `AppIcon` - app icon engine (tray, tray list, tiles, notifications, window switcher, ListRow iconSource, launcher rows, cast picker): `source`, `tray` (SystemTrayItem: NeedsAttention = red corner dot), `size`. Dot-matrix glyph (2 px pitch, 1 px dots; `ink`, `faint` props) in one ink that follows light/dark; baked red badge lights red dots. Shader widgets/appicon.frag(.qsb). `AppIcon { source: modelData.icon; tray: modelData; size: 16 }`

## Desktop widgets (engine: `services/Desk.qml`, `desktop/DeskHost.qml`)
- `UiWidgetCard` - the frame of every desktop widget: glass plate + 1 px outline (`Theme.edge`), optional `caption` (UiCaption), children go into the padded body. `inst` (placement, set by the host), `awake` (the engine's gate: bind EVERY timer / process / SystemClock of a widget to it). Root of a widget file: `UiWidgetCard { ... }`; it is sized by the host (grid cells, `Desk.px(n)`). Widgets live in `desktop/` (built-in) or in a module (manifest `"widgets": "Widgets.qml"`, `defs` list).
  Rules: no looping animation, no polling faster than the data changes, shared data goes into `Desk` (one process for all copies), under Lite / fullscreen the engine stops you (`awake`).

- `UiMenu` - context menu (fills its parent surface; `ax` `ay` = where it opens). `items` = plain objects `{label, icon?, hint?, on? (LED), off?, sub?: [items], act?, keep?, sep?, ask?: {title, text?, accept(text)}}`; thin glass plates (22 px rows, 10 px mono caps, 184 px wide; rare actions go into a "More" submenu), `strip` rows = one row of icon buttons (`{strip: [{icon, off?, act?, ask?}]}`, Win11 style, left/right selects), `info` rows = plain text, hairlines, caret = submenu (opens right, flips left at the edge), `ask` = one-line name field. Keys up/down/left/right/Enter/Esc, hover selects; click outside / Esc / action / lost focus = `done()`. Used by the desktop menu (`Desk.menuItems`), meant for Desk icons, widgets, tray.

## Not shared yet (do not copy them; migrate when touched)
LockContent `Field`, PolkitDialog fields, NotifCard, Settings rows delegate.
- `UiKeyCap` - dim keycap (`k`): the key that does what its row does (Settings Layout inspector).
