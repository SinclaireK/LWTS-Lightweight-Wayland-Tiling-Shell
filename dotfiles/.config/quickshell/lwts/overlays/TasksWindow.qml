// Tasks (Ctrl+Shift+Esc, `qs -c lwts ipc call tasks toggle`): the Windows Task Manager structure, Nothing look, adaptive to any window size.
//   Processes   apps (a window of theirs is open) and background, grouped by process name; sort by header or 1 2 3; / filter; ↑↓ pick;
//               hold Delete (or the End button) = End. Details = every PID. Startup / Services = lists (read-only). Lists scroll.
//   Performance CPU / Memory / Disk / Network / GPU: a list of resources on the left (one column + a back button when narrow), the chosen one
//               on the right: hero numeral, last minute, key / value rows, per-core matrix for CPU.
// Scenarios: wide (>= 760) = left rail; narrow = tabs on top. Master / detail split from 620 wide, below it one pane at a time. Height < 480
// drops the secondary blocks (rows, matrix) and shrinks numerals. Data: services/Tasks.qml.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.services
import qs.widgets

LazyLoader {
  active: Tasks.shown
  FloatingWindow {
    id: win
    visible: true
    title: "LWTS Tasks"
    implicitWidth: 1000; implicitHeight: 700
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, Theme.opacityL0)
    onVisibleChanged: if (!visible) Tasks.shown = false

    FocusScope {
      id: p
      anchors { fill: parent; margins: width < 480 ? 12 : 18 }
      focus: true

      // ---- size classes
      readonly property bool rail: width >= 760
      readonly property bool slim: width < 1100   // icon-only rail
      readonly property real railW: slim ? 44 : 150
      readonly property real cw: width - (rail ? railW + 18 : 0)   // content width
      readonly property bool small: height < 480
      readonly property bool split: cw >= 620
      readonly property bool tight: cw < 400

      // ---- state
      property string tab: Tasks.tab       // proc | perf | start | det | svc
      Connections { target: Tasks; function onResChanged() { if (p.res !== Tasks.res) p.res = Tasks.res }
        function onTabChanged() { if (p.tab !== Tasks.tab) p.tab = Tasks.tab } }
      property string sortBy: "cpu"        // cpu | mem | name
      property string filter: ""
      property string sel: ""              // picked app (by name: the list re-sorts every second)
      property bool filtering: false
      property int page: 0
      property real endK: 0                // hold-to-End progress
      Component.onCompleted: Tasks.wantSys = tab === "perf"
      property string res: Tasks.res           // perf: chosen resource
      property bool detailOpen: false      // perf, narrow: the detail pane instead of the list

      function openSettings(sec, tab) { Quickshell.execDetached(["qs", "-c", "lwts", "ipc", "call", "launcher", "tab", String(sec), String(tab)]); Tasks.shown = false }
      function fmtMem(mb) { return mb >= 1024 ? (mb / 1024).toFixed(1) + " G" : Math.round(mb) + " M" }
      function fmtRate(b) { return b >= 1048576 ? (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) + " MB/s" : Math.round(b / 1024) + " KB/s" }

      function go(t) { tab = t; Tasks.tab = t; detailOpen = false; p.forceActiveFocus() }
      // ---- tables (Processes, Details, Startup, Services): one UiTable, rows and columns per tab
      property string sortKey: "cpu"
      onTabChanged: { Tasks.wantSys = tab === "perf"; filter = ""; sel = ""; sortKey = ({ proc: "cpu", det: "pid", svc: "n", start: "n" })[tab] || ""; Tasks.wantServices = tab === "svc"; Tasks.wantStartup = tab === "start" }
      function cmp(k) { return (x, y) => k === "cpu" || k === "mem" ? y[k] - x[k] : typeof x[k] === "number" ? x[k] - y[k] : String(x[k]).localeCompare(String(y[k])) }
      readonly property var winPids: { const s = ({}); for (const w of Compositor.windowList) if (w.pid) s[w.pid] = true; return s }
      function match(x) { const f = filter.toLowerCase(); return f === "" || x.n.toLowerCase().includes(f) || (x.desc && x.desc.toLowerCase().includes(f)) }
      readonly property var rows: {
        if (tab === "proc") {
          const a = Tasks.apps.filter(match).sort(cmp(sortKey));
          const isApp = x => x.pids.some(pid => winPids[pid]);
          const apps = a.filter(isApp), bg = a.filter(x => !isApp(x)), out = [];
          if (apps.length) { out.push({ hdr: "Apps", count: apps.length }); for (const x of apps) out.push(x) }
          if (bg.length) { out.push({ hdr: "Background", count: bg.length }); for (const x of bg) out.push(x) }
          return out
        }
        if (tab === "det") return Tasks.procs.filter(match).sort(cmp(sortKey));
        if (tab === "svc") return Tasks.services.filter(match).sort(cmp(sortKey));
        if (tab === "start") return Tasks.startup.filter(match).sort(cmp(sortKey));
        return []
      }
      readonly property var columns: {
        const wide = cw >= 560, mem = { k: "mem", label: "Memory", w: 96, right: true, mono: true, fmt: r => fmtMem(r.mem) };
        const cpu = { k: "cpu", label: "CPU", w: wide ? 190 : 84, right: !wide, mono: true, meter: wide ? "cpuN" : "", fmt: r => r.cpu.toFixed(1) + "%", color: r => r.cpu >= 25 ? Theme.red : Theme.text };
        if (tab === "proc") return [{ k: "n", label: "Name", w: 0, kind: r => Kinds.ofProcess(r.n), fmt: r => r.n + (r.c > 1 ? "  x" + r.c : "") }, cpu, mem];
        if (tab === "det") return [{ k: "n", label: "Name", w: 0, kind: r => Kinds.ofProcess(r.n) }, { k: "pid", label: "PID", w: 72, right: true, mono: true }].concat(wide ? [{ k: "st", label: "Status", w: 100, mono: true, fmt: r => ({ R: "Running", S: "Sleeping", D: "Waiting", Z: "Zombie", T: "Stopped", I: "Idle" })[r.st] || r.st }] : []).concat([cpu, mem]);
        if (tab === "svc") return [{ k: "n", label: "Name", w: wide ? 230 : 0 }, { k: "state", label: "Status", w: 110, mono: true, dot: r => r.state === "running", fmt: r => r.state === "running" ? "Running" : r.state === "failed" ? "Failed" : r.sub === "exited" ? "Exited" : "Stopped", color: r => r.state === "failed" ? Theme.red : r.state === "running" ? Theme.text : Theme.dim }].concat(wide ? [{ k: "desc", label: "Description", w: 0 }] : []);
        return [{ k: "n", label: "Name", w: 0 }, { k: "on", label: "Status", w: 110, mono: true, fmt: r => r.on ? "Enabled" : "Disabled", color: r => r.on ? Theme.text : Theme.dim }, { k: "src", label: "Source", w: 100, mono: true }]
      }
      readonly property var totals: ({ cpu: Math.round(SysMon.cpu * 100) + "%", mem: Math.round(SysMon.ram * 100) + "%" })
      readonly property string rowKey: tab === "det" ? "pid" : "n"
      readonly property bool killable: tab === "proc" || tab === "det"
      readonly property var selRow: rows.find(r => !r.hdr && String(r[rowKey]) === sel) || null
      function endSel() { if (!selRow) return; Tasks.end(tab === "proc" ? selRow.pids : [selRow.pid]) }
      Timer { id: holdT; interval: 40; repeat: true
        onTriggered: { p.endK = Math.min(1, p.endK + 40 / 800); if (p.endK >= 1) { stop(); p.endSel(); p.endK = 0 } } }
      function holdStart() { if (killable && selRow && !holdT.running) { endK = 0; holdT.start() } }
      function holdStop() { holdT.stop(); endK = 0 }

      // ---- performance: resources (CPU, Memory, every Disk, every network interface, GPU) and the detail of the chosen one
      readonly property var sd: Tasks.sys
      readonly property var ci: Tasks.cpuInfo
      readonly property real memTotal: SysMon.ram > 0 ? SysMon.ramGb / SysMon.ram : 0
      function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(1) + " TB" : Math.round(b / 1e9) + " GB" }
      function mbs(mb) { return mb >= 1024 ? (mb / 1024).toFixed(1) + " G" : Math.round(mb || 0) + " M" }
      function bytes(b) { return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : Math.round(b / 1e6) + " MB" }
      function upTime(s) { s = Math.floor(s || 0); const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return (d > 0 ? d + "d " : "") + h + "h " + m + "m" }
      function n1(v, d) { return v === undefined || v === null ? "-" : Number(v).toFixed(d === undefined ? 0 : d) }
      function ghz(mhz) { return (mhz / 1000).toFixed(2) + " GHz" }
      readonly property var disks: sd.disks || []
      readonly property var nets: sd.nets || []
      readonly property var resources: {
        if (tab !== "perf") return [];
        Tasks.rev;
        const out = [
          { id: "cpu", name: "CPU", icon: "cpu", v: SysMon.cpu, num: String(Math.round(SysMon.cpu * 100)), unit: "%", sub: SysMon.cpuGhz.toFixed(1) + " GHz" + (SysMon.cpuTemp > 0 ? "  " + SysMon.cpuTemp + "°" : "") },
          { id: "mem", name: "Memory", icon: "memory", v: SysMon.ram, num: String(Math.round(SysMon.ram * 100)), unit: "%", sub: SysMon.ramGb.toFixed(1) + " / " + memTotal.toFixed(0) + " G" }
        ];
        disks.forEach((d, i) => out.push({ id: "disk:" + d.n, name: "Disk " + i + "  " + d.n, icon: "hard-drives", v: (d.active || 0) / 100, num: String(Math.round(d.active || 0)), unit: "%", sub: d.kind + "  " + gb(d.size) + (d.temp ? "  " + Math.round(d.temp) + "°" : "") }));
        nets.forEach(n => { const r = fmtRate((n.rx || 0) + (n.tx || 0)).split(" "); out.push({ id: "net:" + n.n, name: (n.wifi ? "Wi-Fi" : n.tun ? "VPN" : "Ethernet") + "  " + n.n, icon: n.wifi ? "wifi-high" : "plugs-connected", v: Tasks.level("net:" + n.n), num: r[0], unit: r[1], sub: "D " + fmtRate(n.rx || 0) + "  U " + fmtRate(n.tx || 0) }) });
        out.push({ id: "gpu", name: "GPU", icon: "graphics-card", v: SysMon.gpu, num: String(Math.round(SysMon.gpu * 100)), unit: "%", sub: SysMon.vramUsed.toFixed(1) + " / " + SysMon.vramTotal.toFixed(0) + " G" + (SysMon.gpuTemp > 0 ? "  " + SysMon.gpuTemp + "°" : "") });
        return out
      }
      readonly property var cur: resources.find(r => r.id === res) || resources[0] || ({ icon: "cpu", name: "", num: "", unit: "", sub: "", v: 0 })
      // what the detail pane shows: graphs [{label, s, s2}], live [[k, v]] (big numerals), info [[k, v]] (key / value), bar (memory composition)
      readonly property var detail: {
        if (tab !== "perf") return ({ title: "", sub: "", graphs: [], live: [], info: [], bar: null, cores: false });
        Tasks.rev;
        const id = res, m = sd.mem || {}, g = sd.gpu || {};
        const D = { title: cur.name, sub: "", graphs: [], live: [], info: [], bar: null, cores: false };
        if (id === "cpu") {
          const fr = sd.freq || [], avg = fr.length ? fr.reduce((a, x) => a + x, 0) / fr.length : SysMon.cpuGhz * 1000, lo = sd.load || [];
          D.sub = ci["Model name"] || ""; D.cores = true;
          D.graphs = [{ label: "Utilization  60 s", s: Tasks.series("cpu") }];
          D.live = [["Utilization", Math.round(SysMon.cpu * 100) + "%"], ["Speed", ghz(avg)], ["Processes", String(Tasks.procs.length)], ["Threads", n1(sd.threads)], ["Handles", n1(sd.handles)], ["Up time", upTime(sd.up)],
                    ["Load 1 min", lo.length ? n1(lo[0], 2) : "-"], ["Interrupts", n1(sd.intr) + "/s"], ["Context switches", n1(sd.ctxt) + "/s"]];
          D.info = [["Max speed", ci["CPU max MHz"] ? ghz(parseFloat(ci["CPU max MHz"])) : "-"], ["Min speed", ci["CPU min MHz"] ? ghz(parseFloat(ci["CPU min MHz"])) : "-"], ["Sockets", ci["Socket(s):"] || ci["Socket(s)"] || "-"],
                    ["Cores", ci["Core(s) per socket:"] || ci["Core(s) per socket"] || "-"], ["Logical processors", ci["CPU(s):"] || ci["CPU(s)"] || String(Tasks.cores.length)], ["Threads per core", ci["Thread(s) per core:"] || ci["Thread(s) per core"] || "-"],
                    ["L1 data cache", (ci["L1d cache:"] || ci["L1d cache"] || "-").replace(/\s*\(.*\)/, "")], ["L2 cache", (ci["L2 cache:"] || ci["L2 cache"] || "-").replace(/\s*\(.*\)/, "")], ["L3 cache", (ci["L3 cache:"] || ci["L3 cache"] || "-").replace(/\s*\(.*\)/, "")],
                    ["Virtualization", ci["Virtualization:"] || ci["Virtualization"] || "-"], ["Load 5 / 15 min", lo.length > 2 ? n1(lo[1], 2) + "   " + n1(lo[2], 2) : "-"], ["Architecture", ci["Architecture:"] || ci["Architecture"] || "-"], ["Temperature", SysMon.cpuTemp > 0 ? SysMon.cpuTemp + "°C" : "-"]];
        } else if (id === "mem") {
          const used = (m.total || 0) - (m.avail || 0), cache = Math.min(m.avail || 0, (m.cached || 0) + (m.buffers || 0)), free = Math.max(0, (m.avail || 0) - cache);
          D.sub = mbs(m.total) + " total";
          D.graphs = [{ label: "Memory usage  60 s", s: Tasks.series("mem") }].concat(m.swapTotal > 0 ? [{ label: "Swap  " + mbs(m.swapTotal - m.swapFree) + " / " + mbs(m.swapTotal), s: Tasks.series("swap") }] : []);
          D.bar = { segs: [{ v: used, a: 1 }, { v: cache, a: 0.45 }, { v: free, a: 0.16 }], legend: [["In use", mbs(used)], ["Cached", mbs(cache)], ["Free", mbs(free)]] };
          D.live = [["In use", mbs(used)], ["Available", mbs(m.avail)], ["Cached", mbs(m.cached)], ["Buffers", mbs(m.buffers)], ["Dirty", mbs(m.dirty)], ["Slab", mbs(m.slab)], ["Shared", mbs(m.shmem)], ["Committed", mbs(m.committed)], ["Anonymous", mbs(m.anon)]];
          D.info = [["Total", mbs(m.total)], ["Swap total", mbs(m.swapTotal)], ["Swap used", mbs((m.swapTotal || 0) - (m.swapFree || 0))], ["Swap cached", mbs(m.swapCached)]];
        } else if (id.startsWith("disk:")) {
          const d = disks.find(x => "disk:" + x.n === id) || {};
          D.sub = d.model || ""; D.title = cur.name;
          D.graphs = [{ label: "Active time  60 s", s: Tasks.series("diskA:" + d.n) }, { label: "Transfer rate  60 s", s: Tasks.series(id) }];
          D.live = [["Active time", n1(d.active) + "%"], ["Avg response", n1(d.resp, 1) + " ms"], ["Read", fmtRate(d.rd || 0)], ["Write", fmtRate(d.wr || 0)], ["Read IOPS", n1(d.riops)], ["Write IOPS", n1(d.wiops)], ["Queue", n1(d.queue)]];
          D.info = [["Capacity", gb(d.size || 0)], ["Type", d.kind || "-"], ["Model", d.model || "-"], ["Device", "/dev/" + d.n], ["Temperature", d.temp ? Math.round(d.temp) + "°C" : "-"]];
        } else if (id.startsWith("net:")) {
          const n = nets.find(x => "net:" + x.n === id) || {};
          D.sub = (n.ssid ? n.ssid + "  " : "") + (n.ip || "");
          D.graphs = [{ label: "Throughput  60 s   (solid = download, dim = upload)", s: Tasks.series("netRx:" + n.n), s2: Tasks.series("netTx:" + n.n) }];
          D.live = [["Receive", fmtRate(n.rx || 0)], ["Send", fmtRate(n.tx || 0)], ["Received", bytes(n.rxT || 0)], ["Sent", bytes(n.txT || 0)]];
          D.info = [["Adapter", n.n || "-"], ["Type", n.wifi ? "Wi-Fi" : n.tun ? "VPN / tunnel" : "Ethernet"], ["State", n.state || "-"], ["IPv4", n.ip || "-"], ["Link speed", n.link ? n.link + " Mbit/s" : "-"]]
            .concat(n.wifi ? [["SSID", n.ssid || "-"], ["Signal", n.signal !== undefined && n.signal !== null ? n.signal + " dBm" : "-"]] : []);
        } else {
          D.sub = "AMD";
          D.graphs = [{ label: "Utilization  60 s", s: Tasks.series("gpu") }, { label: "Video memory  60 s", s: Tasks.series("gpuVram") }, { label: "Temperature  60 s", s: Tasks.series("gpuTemp") }];
          D.live = [["Utilization", Math.round(SysMon.gpu * 100) + "%"], ["Core clock", g.sclk ? g.sclk + " MHz" : "-"], ["Memory clock", g.mclk ? g.mclk + " MHz" : "-"], ["Power", g.power !== undefined ? n1(g.power) + " / " + n1(g.cap) + " W" : "-"],
                    ["Fan", g.fan !== undefined ? n1(g.fan) + " rpm" : "-"], ["Video memory", SysMon.vramUsed.toFixed(1) + " / " + SysMon.vramTotal.toFixed(0) + " G"], ["Memory busy", g.membusy !== undefined ? n1(g.membusy) + "%" : "-"]];
          D.info = [["Edge", g.tEdge ? Math.round(g.tEdge) + "°C" : "-"], ["Junction", g.tJunc ? Math.round(g.tJunc) + "°C" : "-"], ["Memory", g.tMem ? Math.round(g.tMem) + "°C" : "-"], ["Power limit", g.cap ? n1(g.cap) + " W" : "-"], ["Fan speed", g.fanPct !== undefined ? n1(g.fanPct) + "%" : "-"]];
        }
        return D
      }
      function pickRes(d) { const i = resources.findIndex(r => r.id === res); res = resources[Math.max(0, Math.min(resources.length - 1, i + d))].id }

      Keys.onPressed: e => {
        const tbl = tab !== "perf"
        if (e.key === Qt.Key_Escape) {
          if (filtering) { filtering = false; filterIn.focus = false; p.forceActiveFocus() }
          else if (tbl && filter !== "") filter = ""
          else if (tab === "perf" && !split && detailOpen) detailOpen = false
          else Tasks.shown = false
        }
        else if (e.key === Qt.Key_Tab) { const o = ["proc", "perf", "start", "det", "svc"]; tab = o[(o.indexOf(tab) + 1) % o.length]; Tasks.tab = tab; detailOpen = false }
        else if (tab === "perf" && e.key === Qt.Key_Down) pickRes(1)
        else if (tab === "perf" && e.key === Qt.Key_Up) pickRes(-1)
        else if (tab === "perf" && (e.key === Qt.Key_Return || e.key === Qt.Key_Right) && !split) detailOpen = true
        else if (tab === "perf" && e.key === Qt.Key_Left && !split) detailOpen = false
        else if (tbl && e.key === Qt.Key_Down) table.pick(1)
        else if (tbl && e.key === Qt.Key_Up) table.pick(-1)
        else if (tbl && e.key === Qt.Key_PageDown) table.pick(8)
        else if (tbl && e.key === Qt.Key_PageUp) table.pick(-8)
        else if (tbl && e.key === Qt.Key_Slash) { filtering = true; filterIn.forceActiveFocus() }
        else if (tbl && killable && e.key === Qt.Key_Delete) { if (!e.isAutoRepeat) holdStart() }
        else return
        e.accepted = true
      }
      Keys.onReleased: e => { if (e.key === Qt.Key_Delete && !e.isAutoRepeat) holdStop() }

      RowLayout {
        anchors.fill: parent; spacing: 18
        ColumnLayout {   // the rail
          visible: p.rail
          Layout.preferredWidth: p.railW; Layout.maximumWidth: p.railW; Layout.fillHeight: true; spacing: 6
          UiNavItem { compact: p.slim; label: "Processes"; glyph: "list-bullets"; on: p.tab === "proc"; onClicked: p.go("proc") }
          UiNavItem { compact: p.slim; label: "Performance"; glyph: "gauge"; on: p.tab === "perf"; onClicked: p.go("perf") }
          UiDotLine { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
          UiNavItem { compact: p.slim; label: "Startup apps"; glyph: "rocket-launch"; on: p.tab === "start"; onClicked: p.go("start") }
          UiNavItem { compact: p.slim; label: "Details"; glyph: "list-bullets"; on: p.tab === "det"; onClicked: p.go("det") }
          UiNavItem { compact: p.slim; label: "Services"; glyph: "gear"; on: p.tab === "svc"; onClicked: p.go("svc") }
          Item { Layout.fillHeight: true }
        }
        ColumnLayout {
          Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12

          RowLayout {   // top tabs (no rail)
            visible: !p.rail
            Layout.fillWidth: true; spacing: 8
            UiSegmented { options: p.cw >= 640 ? [["proc", "Processes"], ["perf", "Performance"], ["start", "Startup"], ["det", "Details"], ["svc", "Services"]] : [["proc", "Proc"], ["perf", "Perf"], ["start", "Start"], ["det", "Det"], ["svc", "Svc"]]
                          current: p.tab; onPicked: id => p.go(id) }
            Item { Layout.fillWidth: true }
          }
          UiDotLine { visible: !p.rail; Layout.fillWidth: true }

          // ================= tables
          ColumnLayout {
            visible: p.tab !== "perf"
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            RowLayout {   // filter + count
              Layout.fillWidth: true; Layout.bottomMargin: 8; spacing: 10
              Rectangle {
                Layout.fillWidth: p.tight; Layout.preferredWidth: p.tight ? -1 : 240; Layout.preferredHeight: 26
                radius: Theme.radiusCtl; color: "transparent"
                border.width: p.filtering ? 2 : 1; border.color: p.filtering ? Theme.ring : Theme.edge
                TextInput {
                  id: filterIn
                  anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                  verticalAlignment: TextInput.AlignVCenter; clip: true
                  color: Theme.text; font.family: Theme.label; font.pixelSize: Math.round(11 * Theme.scale); font.capitalization: Font.AllUppercase
                  text: p.filter; onTextChanged: p.filter = text
                  onActiveFocusChanged: p.filtering = activeFocus
                  Keys.onReturnPressed: { p.filtering = false; p.forceActiveFocus() }
                  Keys.onEscapePressed: { text = ""; p.filtering = false; p.forceActiveFocus() }
                  Keys.onDownPressed: { p.filtering = false; p.forceActiveFocus(); table.pick(1) }
                  UiCaption { visible: filterIn.text === "" && !filterIn.activeFocus; text: "/ filter"; anchors.verticalCenter: parent.verticalCenter }
                }
              }
              Item { Layout.fillWidth: !p.tight }
              UiCaption { visible: !p.tight; text: p.rows.filter(r => !r.hdr).length + (p.tab === "svc" ? " services" : p.tab === "start" ? " apps" : " processes") }
            }
            UiTable {
              id: table
              Layout.fillWidth: true; Layout.fillHeight: true
              columns: p.columns; rows: p.rows; totals: p.totals; rowKey: p.rowKey; sortBy: p.sortKey; rowH: p.small ? 28 : 32
              sel: p.sel; onSelChanged: p.sel = sel
              onSortRequested: key => p.sortKey = key
            }
            UiDotLine { visible: p.killable; Layout.fillWidth: true }
            RowLayout {   // footer: the picked one + End (hold)
              visible: p.killable
              Layout.fillWidth: true; Layout.topMargin: 8; spacing: 8
              Item { Layout.fillWidth: true }
              UiCaption { visible: !p.tight && !!p.selRow; text: p.selRow ? p.selRow.n : "" }
              DotMeter { visible: p.endK > 0; count: 10; dotSize: 5; gap: 3; value: p.endK; litColor: Theme.red }
              UiButton {
                text: "End"; enabled: !!p.selRow
                MouseArea { anchors.fill: parent; enabled: !!p.selRow; onPressed: p.holdStart(); onReleased: p.holdStop(); onCanceled: p.holdStop() }
              }
            }
          }

          // ================= Performance
          Loader {   // built only while the tab is open: its bindings (resources, detail, four graphs) refresh every second
            active: p.tab === "perf"
            visible: active
            Layout.fillWidth: true; Layout.fillHeight: true
            sourceComponent: perfPage
          }
        }
      }

      Component {
        id: perfPage
            RowLayout {
              Layout.fillWidth: true; Layout.fillHeight: true; spacing: 18

              Flickable {   // the resources (a card per disk / interface, so it can grow: it scrolls)
                visible: p.split || !p.detailOpen
                Layout.preferredWidth: p.split ? Math.max(170, Math.min(210, p.cw * 0.22)) : -1; Layout.maximumWidth: p.split ? 210 : 100000
                Layout.fillWidth: !p.split; Layout.fillHeight: true
                contentHeight: cards.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: cards
                  width: parent.width
                  Repeater {
                    model: p.resources.length   // a count, not the array: the array is rebuilt every second and would rebuild every card
                    Item {
                      id: card
                      required property int index
                      readonly property var modelData: p.resources[index] || ({ id: "", name: "", icon: "cpu", v: 0, num: "", unit: "", sub: "" })
                      readonly property bool on: card.modelData.id === p.res
                      width: cards.width; height: p.small ? 58 : 84
                      Rectangle { anchors.fill: parent; anchors.margins: 2; radius: Theme.radiusInner; color: "transparent"; border.width: card.on && p.split ? 1 : 0; border.color: Theme.text }
                      Rectangle { anchors.fill: parent; anchors.margins: 2; radius: Theme.radiusInner; color: Theme.fillHover; visible: !(card.on && p.split) && cardMa.containsMouse }
                      MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                  onClicked: { p.res = card.modelData.id; p.detailOpen = !p.split; p.forceActiveFocus() } }
                      ColumnLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 6; bottomMargin: 6 }
                        spacing: 3
                        Item { Layout.fillHeight: true }
                        RowLayout {
                          Layout.fillWidth: true; spacing: 8
                          Icon { name: card.modelData.icon; color: card.on ? Theme.text : Theme.dim; font.pixelSize: 14 }
                          UiCaption { text: card.modelData.name; color: card.on ? Theme.text : Theme.dim; Layout.fillWidth: true; elide: Text.ElideRight }
                          Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.red; opacity: card.modelData.v > 0.9 ? 1 : 0 }
                          UiNum { text: card.modelData.num; size: Math.round((p.small ? 14 : 18) * Theme.scale); color: card.modelData.v > 0.9 ? Theme.red : Theme.text }
                          UiCaption { text: card.modelData.unit }
                        }
                        Item { Layout.fillWidth: true; implicitHeight: 6
                          DotMeter { anchors.verticalCenter: parent.verticalCenter; fit: parent.width; dotSize: 3; gap: 2; value: card.modelData.v; hot: 0.9; hotColor: Theme.red } }
                        UiCaption { visible: !p.small; text: card.modelData.sub; Layout.fillWidth: true; elide: Text.ElideRight }
                        Item { Layout.fillHeight: true }
                      }
                    }
                  }
                }
              }
              Rectangle { visible: p.split; Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.line }

              Flickable {   // the chosen one: header, graphs, live numbers, facts, cores
                id: dv
                visible: p.split || p.detailOpen
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: dcol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                readonly property int liveCols: width >= 760 ? 4 : width >= 480 ? 3 : 2
                ColumnLayout {
                  id: dcol
                  width: dv.width - (dv.contentHeight > dv.height ? 10 : 0); spacing: 12
                  RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    UiIconButton { visible: !p.split; icon: "caret-left"; size: 24; onClicked: p.detailOpen = false }
                    Icon { name: p.cur.icon; color: Theme.text; font.pixelSize: 16 }
                    UiCaption { text: p.detail.title; color: Theme.text; font.pixelSize: Math.round(12 * Theme.scale) }
                    Item { Layout.fillWidth: true }
                    UiCaption { text: p.detail.sub; Layout.maximumWidth: dv.width * 0.6; elide: Text.ElideRight }
                  }
                  RowLayout {   // hero
                    spacing: 6
                    UiNum { text: p.cur.num; size: Math.round((p.small ? 34 : p.tight ? 44 : 64) * Theme.scale); color: p.cur.v > 0.9 ? Theme.red : Theme.text }
                    UiCaption { text: p.cur.unit; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: p.small ? 4 : 10 }
                    Item { Layout.fillWidth: true }
                    UiCaption { text: p.cur.sub; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 10 }
                  }
                  Repeater {   // graphs: the first one is tall, the rest slimmer
                    model: p.detail.graphs.length
                    ColumnLayout {
                      required property int index
                      readonly property var modelData: p.detail.graphs[index] || ({ label: "", s: [] })
                      Layout.fillWidth: true; spacing: 6
                      UiCaption { text: modelData.label }
                      DotGraph {
                        Layout.fillWidth: true; Layout.preferredHeight: index === 0 ? Math.max(110, Math.min(260, p.height * 0.24)) : 70
                        rev: Tasks.rev; series: modelData.s; series2: modelData.s2 || []
                        pitch: p.small || p.tight ? 5 : 6; dot: p.small || p.tight ? 3 : 4
                      }
                    }
                  }
                  ColumnLayout {   // memory: In use / Cached / Free in one dotted bar
                    visible: !!p.detail.bar
                    Layout.fillWidth: true; spacing: 6
                    UiCaption { text: "Composition" }
                    UiComposeBar { Layout.fillWidth: true; segments: p.detail.bar ? p.detail.bar.segs : [] }
                    RowLayout {
                      spacing: 18
                      Repeater {
                        model: p.detail.bar ? p.detail.bar.legend.length : 0
                        RowLayout {
                          required property int index
                          readonly property var modelData: p.detail.bar && p.detail.bar.legend[index] || ["", ""]
                          spacing: 6
                          Rectangle { width: 6; height: 6; radius: 3; color: Theme.text; opacity: [1, 0.45, 0.16][index] }
                          UiCaption { text: modelData[0] }
                          UiCaption { text: modelData[1]; color: Theme.text }
                        }
                      }
                    }
                  }
                  UiDotLine { Layout.fillWidth: true }
                  GridLayout {   // live numbers
                    Layout.fillWidth: true; columns: dv.liveCols; columnSpacing: 20; rowSpacing: 14; uniformCellWidths: true
                    Repeater {
                      model: p.detail.live.length
                      ColumnLayout {
                        required property int index
                        readonly property var modelData: p.detail.live[index] || ["", ""]
                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 3
                        UiCaption { text: modelData[0] }
                        UiNum { text: modelData[1]; size: Math.round(18 * Theme.scale) }
                      }
                    }
                  }
                  UiDotLine { visible: p.detail.info.length > 0; Layout.fillWidth: true }
                  GridLayout {   // facts
                    visible: p.detail.info.length > 0
                    Layout.fillWidth: true; columns: dv.width >= 640 ? 2 : 1; columnSpacing: 36; rowSpacing: 6; uniformCellWidths: true
                    Repeater {
                      model: p.detail.info.length
                      RowLayout {
                        required property int index
                        readonly property var modelData: p.detail.info[index] || ["", ""]
                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 8
                        UiCaption { text: modelData[0] }
                        Item { Layout.fillWidth: true }
                        UiCaption { text: modelData[1]; color: Theme.text; Layout.maximumWidth: dv.width * 0.3; elide: Text.ElideRight }
                      }
                    }
                  }
                  ColumnLayout {   // CPU: per core, the load and the clock
                    visible: p.detail.cores
                    Layout.fillWidth: true; spacing: 8
                    UiDotLine { Layout.fillWidth: true }
                    UiCaption { text: "Cores  " + Tasks.cores.length }
                    GridLayout {
                      Layout.fillWidth: true
                      columns: Math.max(1, Math.min(4, Math.floor(dv.width / 230))); columnSpacing: 20; rowSpacing: 6
                      Repeater {
                        model: Tasks.cores.length
                        RowLayout {
                          required property int index
                          Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 6
                          UiCaption { Layout.preferredWidth: 16; text: index; horizontalAlignment: Text.AlignRight }
                          Item { Layout.fillWidth: true; implicitHeight: 4
                            DotMeter { anchors.verticalCenter: parent.verticalCenter; fit: parent.width; dotSize: 3; gap: 2; value: Tasks.cores[index] || 0; hot: 0.9; hotColor: Theme.red } }
                          UiCaption { Layout.preferredWidth: 26; text: Math.round((Tasks.cores[index] || 0) * 100) + "%"; color: Theme.text; horizontalAlignment: Text.AlignRight }
                          UiCaption { Layout.preferredWidth: 52; text: (p.sd.freq && p.sd.freq[index] ? (p.sd.freq[index] / 1000).toFixed(2) : "-") + " G"; horizontalAlignment: Text.AlignRight }
                        }
                      }
                    }
                  }
                  Item { implicitHeight: 8 }
                }
              }
            }
      }
    }
  }
}
