// The Gaming category (moved from settings/SettingsNew.qml): GPU, MangoHud overlay, Lite (game mode), per-game environment, tuning.
// A module may bring a whole category: `sectionDef` (services/Modules.qml extend()). Kernels stays in the base (System).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core
import qs.services

Scope {
  id: root
  property string section: "gaming"
  property var sectionDef: ({ id: "gaming", icon: "game-controller", label: "Gaming", before: "system" })
  readonly property bool open: Modules.openSection === "gaming" || Modules.openSection === "system"
  readonly property bool laptop: !!UPower.displayDevice && UPower.displayDevice.isLaptopBattery
  function choice(label, desc, options, get, set) { return { type: options.length > 3 || options.some(o => String(o[1]).length > 18) ? "cycle" : "choice", label, desc, options, get, set } }
  function cycle(label, desc, options, get, set) { return { type: "cycle", label, desc, options, get, set } }
  function multi(label, desc, options, isOn, toggle) { return { type: "multi", label, desc, options, isOn, toggle } }
  function slider(label, desc, steps, unit, get, set) { return { type: "slider", label, desc, steps, unit, get, set } }
  function input(label, desc, get, set, o) { return Object.assign({ type: "input", label, desc, get, set }, o || {}) }
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  function info(label, value) { return { type: "info", label, value } }

    function mangoSet(key, v) {   // MangoHud keys: saved, then theme.py rewrites ~/.config/MangoHud/MangoHud.conf
      Prefs.set(key, v); Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/themes/theme.py", "mangohud"]);
    }
    // MangoHud constructor (Gaming -> Overlay): the shown metrics are one list in settings.toml (mango_metrics); theme.py writes MangoHud.conf
    readonly property var mangoGroups: [
      ["Frame rate", [["fps", "FPS"], ["frame_timing", "Frame time graph"], ["fps_metrics", "Average and 1% low"], ["show_fps_limit", "Current FPS limit"]]],
      ["Graphics card", [["gpu_stats", "Load"], ["gpu_temp", "Temperature"], ["gpu_core_clock", "Core clock"], ["gpu_mem_clock", "Memory clock"], ["gpu_power", "Power"], ["gpu_voltage", "Voltage"], ["vram", "Video memory"]]],
      ["Processor and memory", [["cpu_stats", "Load"], ["cpu_temp", "Temperature"], ["cpu_mhz", "Clock"], ["ram", "Memory"]]],
      ["System", [["present_mode", "Present mode"], ["vulkan_driver", "Vulkan driver"], ["engine_version", "Game engine"], ["wine", "Wine / Proton"], ["display_server", "Display server"]]]]
    readonly property var mangoPresets: ({
      fps: ["fps"], basic: ["fps", "gpu_stats", "gpu_temp", "cpu_stats", "cpu_temp"],
      full: [].concat(...mangoGroups.map(g => g[1].map(m => m[0]))) })
    function mangoMetrics() { const m = Prefs.get("mango_metrics", null); return Array.isArray(m) ? m : (mangoPresets[Prefs.get("mango_preset", "full")] || mangoPresets.full) }
    function mangoToggle(id) { const m = mangoMetrics(); mangoSet("mango_metrics", m.indexOf(id) >= 0 ? m.filter(x => x !== id) : m.concat([id])) }
    function mangoPresetNow() { const m = mangoMetrics().slice().sort().join(); return Object.keys(mangoPresets).find(k => mangoPresets[k].slice().sort().join() === m) || "" }
    function mangoPresetList() { const l = Prefs.get("mango_presets", []); return Array.isArray(l) ? l.filter(x => typeof x === "string" && x.indexOf("|") > 0) : [] }
    function mangoSavePreset(name) {
      const list = mangoPresetList().filter(x => x.split("|")[0] !== name).concat([name + "|" + mangoMetrics().join(",")]);
      mangoSet("mango_presets", list.slice(0, 8));
    }
    function mangoDelPreset(name) { mangoSet("mango_presets", mangoPresetList().filter(x => x.split("|")[0] !== name)) }
    function mangoUsePreset(x) { mangoSet("mango_metrics", x.split("|")[1].split(",").filter(i => i)) }
    // Gaming -> Environment: files in ~/.config/lwts/game-env (global.env, <appid>.env), edited by scripts/game-env.lua, read by lwts-game / steam-launch
    readonly property string home: Quickshell.env("HOME")
    readonly property string envTool: home + "/.config/quickshell/lwts/scripts/game-env.lua"
    // groups of ready options: {n: variable, v: value (on/off row) | p: [[value, label]] (pick row), l: label, d: description, hw: amd|intel|nvidia (optional)};
    // a group shows only when its package / graphics card exists. Names come from the Proton-CachyOS README, DXVK, vkd3d-proton, Mesa and NVIDIA docs
    readonly property var envGroups: [
      ["Launch wrappers", "", [
        { n: "LWTS_MANGOHUD", p: [["1", "On"], ["dlsym", "On, for OpenGL games (--dlsym)"]], l: "MangoHud overlay", d: "Shows FPS and frame time in the game; look is set in Overlay. With Gamescope it becomes Gamescope's own overlay", hw: "mangohud" },
        { n: "LWTS_GAMESCOPE", txt: true, l: "Gamescope arguments", d: "Runs the game inside Gamescope. Empty = off. Flags: -W -H output size, -w -h game size, -r FPS, -F fsr|nis|linear, -S fit|integer, -f fullscreen, --adaptive-sync, --hdr-enabled, --framerate-limit", hw: "gamescope" }]],
      ["Proton CachyOS", "proton", [
        { n: "PROTON_ENABLE_WAYLAND", v: "1", l: "Wayland window", d: "Native Wayland window instead of XWayland; experimental" },
        { n: "PROTON_NO_NTSYNC", v: "1", l: "NTSync off", d: "NTSync is on by default and faster; turn it off only if a game crashes" },
        { n: "PROTON_PREFER_SDL", v: "1", l: "SDL controller input", d: "SDL instead of Steam Input; for gamepads that are not detected" },
        { n: "PROTON_LOCAL_SHADER_CACHE", v: "1", l: "Own shader cache", d: "A shader cache per game even when Steam pre-caching is off" },
        { n: "PROTON_DXVK_LOWLATENCY", v: "1", l: "DXVK low latency", d: "The low-latency DXVK fork: steadier frame pacing in Direct3D 9-11 games" },
        { n: "PROTON_VKD3D_LOWLATENCY", v: "1", l: "VKD3D low latency", d: "The low-latency VKD3D fork for Direct3D 12 games" },
        { n: "DXVK_HDR", v: "1", l: "HDR", d: "Needs an HDR screen and HDR on in the compositor" },
        { n: "PROTON_USE_WINED3D", v: "1", l: "OpenGL renderer (old games)", d: "wined3d instead of DXVK; only for old games that fail with DXVK" },
        { n: "PROTON_XESS_UPGRADE", v: "1", l: "XeSS upgrade", d: "Swaps in a newer Intel XeSS library" },
        { n: "PROTON_FSR4_UPGRADE", v: "1", l: "FSR 4 upgrade", d: "Upgrades FSR 3.1 games to FSR 4; meant for new Radeon cards, check the game", hw: "amd" },
        { n: "PROTON_DLSS_UPGRADE", v: "1", l: "DLSS upgrade", d: "Downloads a newer DLSS library for the game", hw: "nvidia" },
        { n: "PROTON_DLSS_INDICATOR", v: "1", l: "DLSS indicator", d: "A small DLSS overlay in the corner", hw: "nvidia" },
        { n: "PROTON_NVIDIA_LIBS", v: "1", l: "NVIDIA libraries", d: "NVENC, CUDA, NVML and OptiX inside the game", hw: "nvidia" },
        { n: "PROTON_HIDE_NVIDIA_GPU", v: "1", l: "Hide the NVIDIA card", d: "For games that refuse to start on NVIDIA", hw: "nvidia" }]],
      ["Frame rate and queue", "", [
        { n: "DXVK_FRAME_RATE", num: [1, 1000], l: "FPS limit: Direct3D 9-11", d: "DXVK limiter (Proton turns it into DXVK_CONFIG). Empty = no limit. OpenGL games: use MangoHud's limit or gamescope" },
        { n: "VKD3D_FRAME_RATE", num: [1, 1000], l: "FPS limit: Direct3D 12", d: "VKD3D-Proton limiter. Empty = no limit" },
        { cfg: ["dxgi.maxFrameLatency", "d3d9.maxFrameLatency"], num: [1, 16], l: "Frame queue (DX 9-11)", d: "How many frames the game may prepare ahead: fewer means less input lag but a less steady frame time. Empty = the game decides" },
        { cfg: ["dxgi.syncInterval", "d3d9.presentInterval"], p: [["0", "Off"], ["1", "On"]], l: "VSync (DX 9-11)", d: "Forces VSync on or off whatever the game asks; off can tear" },
        { cfg: ["dxvk.tearFree"], p: [["True", "Mailbox (no tearing)"], ["False", "Relaxed FIFO (may tear)"]], l: "Presentation mode (DX 9-11)", d: "DXVK: True uses mailbox when VSync is off; False uses relaxed FIFO when VSync is on, which can tear to reduce stutter" },
        { cfg: ["dxvk.latencySleep"], p: [["True", "On"], ["False", "Off"]], l: "Latency sleep (DX 9-11)", d: "DXVK paces frames to cut input lag; Auto when empty" },
        { n: "VKD3D_SWAPCHAIN_PRESENT_MODE", p: [["MAILBOX", "Mailbox (no tearing)"], ["IMMEDIATE", "Immediate (tearing)"], ["FIFO", "VSync (FIFO)"], ["FIFO_RELAXED", "Relaxed FIFO"]], l: "Presentation mode (DX 12)", d: "How VKD3D-Proton hands frames to the screen" }]],
      ["DXVK, VKD3D and Wine", "", [
        { n: "DXVK_HUD", p: [["fps", "FPS"], ["fps,frametimes", "FPS and frame graph"], ["full", "Everything"]], l: "DXVK overlay", d: "DXVK's own overlay in Direct3D games; MangoHud covers every game" },
        { n: "VKD3D_CONFIG", p: [["nodxr", "No ray tracing"], ["single_queue", "No async compute"]], l: "Direct3D 12 tweaks", d: "VKD3D-Proton switches; try them when a DX12 game crashes or glitches" },
        { n: "WINEDEBUG", v: "-all", l: "Quiet Wine", d: "Turns Wine's debug output off; a little less CPU work" }]],
      ["Mesa", "mesa", [
        { n: "mesa_glthread", v: "true", l: "OpenGL threading", d: "OpenGL calls run on a second thread; helps some older games" },
        { n: "MESA_SHADER_CACHE_MAX_SIZE", p: [["4G", "4 GB"], ["12G", "12 GB"]], l: "Shader cache size", d: "The default is 1 GB; a bigger cache means fewer stutters" },
        { n: "MESA_VK_WSI_PRESENT_MODE", p: [["mailbox", "Mailbox (no tearing, low lag)"], ["immediate", "Immediate (tearing)"], ["fifo", "VSync (FIFO)"]], l: "Vulkan presentation mode", d: "Forces how Vulkan games show frames (Radeon and Intel)" },
        { n: "MESA_NO_ERROR", v: "1", l: "No OpenGL error checks", d: "A little faster; a game that misuses the API may crash. Careful" }]],
      ["AMD Radeon", "amd", [
        { n: "RADV_PERFTEST", v: "sam", l: "Smart Access Memory", d: "Puts more driver objects in video memory; needs Resizable BAR on" },
        { n: "RADV_TEX_ANISO", v: "16", l: "16x anisotropic filtering", d: "Sharper textures at a distance for a small cost" }]],
      ["Intel graphics", "intel", [
        { n: "ANV_SYS_MEM_LIMIT", p: [["50", "50%"], ["90", "90%"]], l: "Vulkan memory limit", d: "Share of RAM the Vulkan driver may use; the default is 75%" },
        { n: "ANV_DEBUG", v: "no-gpl", l: "No pipeline library", d: "Turns off the graphics pipeline library; a workaround when a game misbehaves" }]],
      ["NVIDIA", "nvidia", [
        { n: "__GL_THREADED_OPTIMIZATIONS", v: "1", l: "OpenGL threading", d: "OpenGL work on a worker thread; off by default" },
        { n: "__GL_SHADER_DISK_CACHE_SIZE", v: "12000000000", l: "Bigger shader cache (12 GB)", d: "Set it for all games: if one game sets it alone, the others reset the cache" },
        { n: "__GL_VRR_ALLOWED", v: "0", l: "G-Sync off", d: "Turns adaptive sync off for the game" },
        { n: "__GL_SYNC_TO_VBLANK", v: "0", l: "VSync off (OpenGL)", d: "Frames are shown without waiting for the screen; tearing possible" },
        { n: "__GL_SHARPEN_ENABLE", v: "1", l: "Image sharpening", d: "Driver sharpening for OpenGL and Vulkan" }]],
      ["Diagnostics", "", [
        { n: "PROTON_LOG", v: "1", l: "Proton log", d: "Writes steam-<appid>.log in your home folder; for finding why a game does not start" },
        { n: "DXVK_LOG_LEVEL", v: "info", l: "DXVK log", d: "More detail in DXVK's log file" }]]]
    property var envHw: ({})   // graphics cards: amd, intel, nvidia
    Process {
      id: envHwScan
      command: ["bash", "-c", "lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' | grep -o '\\[\\(1002\\|8086\\|10de\\):' | tr -d '[:'; for p in mangohud gamescope; do pacman -Q $p >/dev/null 2>&1 && echo $p; done"]
      stdout: StdioCollector { onStreamFinished: { const t = this.text.split("\n"); root.envHw = { amd: t.indexOf("1002") >= 0, intel: t.indexOf("8086") >= 0, nvidia: t.indexOf("10de") >= 0, mangohud: t.indexOf("mangohud") >= 0, gamescope: t.indexOf("gamescope") >= 0 } } }
    }
    function envShow(need) { return need === "" || (need === "proton" ? !!tun.protonPkg : need === "mesa" ? !!(envHw.amd || envHw.intel) : !!envHw[need]) }
    function envKnown() { return envGroups.reduce((a, g) => a.concat(g[2].map(it => it.n || "DXVK_CONFIG")), []) }
    // DXVK_CONFIG holds "key = value; key = value": cfg items edit single keys inside it
    function cfgParse(list) { return (envVal(list, "DXVK_CONFIG") || "").split(";").map(x => x.trim()).filter(x => x).map(x => { const i = x.indexOf("="); return [x.slice(0, i).trim(), x.slice(i + 1).trim()] }) }
    function cfgGet(list, key) { const e = cfgParse(list).find(x => x[0] === key); return e ? e[1] : "" }
    function cfgSet(scope, list, keys, v) {
      const rest = cfgParse(list).filter(x => keys.indexOf(x[0]) < 0).concat(v === "" ? [] : keys.map(k => [k, v])).map(x => x[0] + " = " + x[1]).join("; ")
      if (rest) envSet(scope, "DXVK_CONFIG", rest); else envDel(scope, "DXVK_CONFIG")
    }
    function envItemRow(scope, list, it) {
      const get = () => it.cfg ? cfgGet(list, it.cfg[0]) : (envVal(list, it.n) || ""), set = v => it.cfg ? cfgSet(scope, list, it.cfg, v) : (v === "" ? envDel(scope, it.n) : envSet(scope, it.n, v))
      if (it.num) return input(it.l, it.d, get, v => set(String(v).trim()), { placeholder: it.num[0] + "–" + it.num[1] + ", empty = off",
                                    validate: t => { t = String(t).trim(); return t === "" || (/^\d{1,4}$/.test(t) && Number(t) >= it.num[0] && Number(t) <= it.num[1]) ? "" : "A number from " + it.num[0] + " to " + it.num[1] } })
      if (it.txt) return input(it.l, it.d, get, v => set(String(v).trim()), { placeholder: "-W 2560 -H 1440 -r 144 -F fsr -f", validate: t => t === "" || /^[\w\s\-.,=:\/]{1,150}$/.test(t) ? "" : "Letters, digits, spaces and - . , = : /" })
      if (it.p) return cycle(it.l, it.d, [["", "Off"]].concat(it.p), get, set)
      return choice(it.l, it.d, [["off", "Off"], ["on", "On"]], () => envVal(list, it.n) === it.v ? "on" : "off", v => v === "on" ? envSet(scope, it.n, it.v) : envDel(scope, it.n))
    }
    function envGroupRows(scope, list) {
      let out = []
      for (const g of envGroups) {
        if (!envShow(g[1])) continue
        const items = g[2].filter(it => !it.hw || envHw[it.hw]); if (!items.length) continue
        out.push(header(g[0])); for (const it of items) out.push(envItemRow(scope, list, it))
      }
      return out
    }
    property string envApp: ""
    property var envGames: []
    property var envGlobal: []
    property var envOwn: []
    property string envMsg: ""
    function envParse(lines) { return lines.filter(l => l.indexOf("=") > 0).map(l => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]) }
    function envRefresh() { envRead.command = ["bash", "-c", envTool + " games; echo '===='; " + envTool + " get global; echo '===='; " + (envApp ? envTool + " get " + envApp : "true")]; envRead.running = true }
    function envSet(scope, k, v) { envRun.command = [envTool, "set", scope, k, v]; envRun.running = true }
    function envDel(scope, k) { envRun.command = [envTool, "del", scope, k]; envRun.running = true }
    function envVal(list, k) { const e = list.find(x => x[0] === k); return e ? e[1] : null }
    function envAdd(scope, text) { const i = text.indexOf("="); envSet(scope, text.slice(0, i).trim(), text.slice(i + 1).trim()) }
    function envCheck(t) { return /^[A-Za-z_][A-Za-z0-9_]{0,63}=[^\n]{1,200}$/.test(t.trim()) ? "" : "NAME=value, letters digits _" }
    onEnvAppChanged: if (open) envRefresh()
    onOpenChanged: if (open) { envRefresh(); envHwScan.running = true; tunScan.running = true }
    Process {
      id: envRead
      stdout: StdioCollector { onStreamFinished: {
        const parts = this.text.split("====\n");
        root.envGames = (parts[0] || "").trim().split("\n").filter(l => l).map(l => l.split("\t"));
        root.envGlobal = root.envParse((parts[1] || "").trim().split("\n"));
        root.envOwn = root.envParse((parts[2] || "").trim().split("\n"));
      } }
    }
    Process { id: envRun; onExited: code => { root.envMsg = code === 0 ? "" : "Not saved"; root.envRefresh() } }
    function envRows(scope, list, skipReady) {
      const ready = skipReady ? envKnown() : [];
      return list.filter(x => ready.indexOf(x[0]) < 0).map(x => ({ type: "action", label: x[0], desc: x[1], buttons: [["Delete", () => envDel(scope, x[0])]] }));
    }

    // Lite mode levels (Gaming -> Game mode): what game-mode.lua switches off; the eight switches stay as "Custom"
    readonly property var liteIds: ["game_animations", "game_blur", "game_rounding", "game_transparency", "game_nightlight", "game_bar_margins", "game_idle", "game_power"]
    readonly property var liteLevels: ({ light: ["game_animations", "game_blur", "game_rounding"],
      medium: ["game_animations", "game_blur", "game_rounding", "game_transparency", "game_nightlight", "game_bar_margins"], max: liteIds })
    property bool liteCustom: false
    function liteOn(id) { return Prefs.get(id, true) !== false }
    function liteLevel() { const on = liteIds.filter(liteOn).join(); return Object.keys(liteLevels).find(k => liteLevels[k].join() === on) || "" }
    function liteSet(level) {
      if (level === "custom") { liteCustom = true; return }
      liteCustom = false; const o = {}; for (const id of liteIds) o[id] = liteLevels[level].indexOf(id) >= 0; Prefs.setMany(o);
    }
    function mangoKeys(extra) { return [["", "Default"]].concat(extra) }
    // Gaming -> GPU (R1): lwts-priv gpu-read is plain sysfs, no root; polled only while the Gaming section is open
    property var gpuInfo: ({})
    Process {
      id: gpuInfoScan
      command: ["/usr/local/libexec/lwts-priv", "gpu-read"]
      stdout: StdioCollector { onStreamFinished: {
        const o = {}; for (const l of this.text.trim().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1) }
        root.gpuInfo = o;
      } }
    }
    Timer { id: gpuInfoTimer; interval: 2000; running: open; repeat: true; triggeredOnStart: true; onTriggered: gpuInfoScan.running = true }
    function gi(k, unit) { const v = gpuInfo[k]; return v === undefined || v === "" ? "—" : v + (unit ? " " + unit : "") }

    // Gaming -> GPU write: sliders edit a draft; Apply writes through lwts-priv (pkexec) and starts a 15 s "keep?" countdown,
    // no answer = the previous values come back (GPU hang or a wrong click must not leave the card in a bad state)
    property var gpuDraft: ({})
    property var gpuPrev: null
    property int gpuCountdown: 0
    property string gpuMsg: ""
    property string gpuMode: ""          // what gpuRun is doing: apply | revert | reset | persist
    function dv(k) { return gpuDraft[k] !== undefined ? gpuDraft[k] : Number(gpuInfo[k]) }
    function setDraft(k, v) { const d = Object.assign({}, gpuDraft); d[k] = v; gpuDraft = d }
    function span(a, b, stepBy) { const r = []; for (let v = a; v < b; v += stepBy) r.push(v); r.push(b); return r }
    function vals(o) { return [o.smin, o.smax, o.mclk, o.vo, o.cap].map(v => String(Math.round(Number(v)))) }
    function gpuRunCmd(mode, args) { gpuMode = mode; gpuRun.command = ["pkexec", "/usr/local/libexec/lwts-priv"].concat(args); gpuRun.running = true }
    function gpuApplyDraft() {
      if (!gpuInfo.smin) return;
      const d = { smin: dv("smin"), smax: dv("smax"), mclk: dv("mclk"), vo: dv("vo"), cap: dv("cap") };
      if (!gpuPrev) gpuPrev = { smin: gpuInfo.smin, smax: gpuInfo.smax, mclk: gpuInfo.mclk, vo: gpuInfo.vo, cap: gpuInfo.cap };
      gpuRunCmd("apply", ["gpu-apply"].concat(vals(d)));
    }
    function gpuKeep() { gpuCountdown = 0; gpuPrev = null; gpuMsg = "Kept until reboot (use Save for boot to make it permanent)" }
    function gpuRevert(why) { if (!gpuPrev) return; gpuCountdown = 0; gpuRunCmd("revert", ["gpu-apply"].concat(vals(gpuPrev))); gpuMsg = why }
    Process {
      id: gpuRun
      stderr: StdioCollector { id: gpuErr }
      onExited: code => {
        if (code !== 0) { root.gpuMsg = (gpuErr.text.trim().split("\n").pop() || ("failed, code " + code)); root.gpuCountdown = 0; if (root.gpuMode === "apply" && !root.gpuPrevApplied) root.gpuPrev = null }
        else if (root.gpuMode === "apply") { root.gpuDraft = ({}); root.gpuCountdown = 15; root.gpuMsg = "Applied" }
        else if (root.gpuMode === "revert") { root.gpuPrev = null; root.gpuDraft = ({}) }
        else if (root.gpuMode === "reset") { root.gpuPrev = null; root.gpuDraft = ({}); root.gpuMsg = "Driver defaults restored" }
        else if (root.gpuMode === "persist") root.gpuMsg = "Saved: the values are applied at every boot";
        gpuInfoScan.running = true;
      }
    }
    property bool gpuPrevApplied: false
    Timer { interval: 1000; repeat: true; running: root.gpuCountdown > 0
            onTriggered: { root.gpuCountdown--; if (root.gpuCountdown === 0) root.gpuRevert("No answer - previous values restored") } }

    // ---- System -> Tuning (settings_redesign 4.12): CachyOS repo status, sched_ext (scxctl talks to scx_loader), a few services ----
    property var tun: ({})
    Process {
      id: tunScan
      command: ["bash", "-c", "grep -q '^\\[cachyos' /etc/pacman.conf 2>/dev/null && echo yes || echo no; "
        + "/lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3 (supported' && echo yes || echo no; "
        + "scxctl get 2>/dev/null | head -1; "
        + "for u in ananicy-cpp systemd-oomd scx_loader; do echo \"$(systemctl is-enabled $u 2>/dev/null)/$(systemctl is-active $u 2>/dev/null)\"; done; "
        + "for p in ananicy-cpp cachyos-ananicy-rules dmemcg-booster proton-cachyos-slr; do pacman -Q $p >/dev/null 2>&1 && echo yes || echo no; done; "
        + "echo \"$(systemctl --user is-enabled dmemcg-booster-user 2>/dev/null)/$(systemctl --user is-active dmemcg-booster-user 2>/dev/null)\"; "
        + "echo \"$(systemctl is-enabled bpftune 2>/dev/null)/$(systemctl is-active bpftune 2>/dev/null)\"; "
        + "scxctl modes -s $(scxctl get 2>/dev/null | awk '{print tolower($2)}') 2>/dev/null | head -1 | sed 's/.*\\[//; s/\\].*//'; "
        + "grep -m1 '^default_sched' /etc/scx_loader.toml 2>/dev/null | sed 's/.*\"scx_\\(.*\\)\".*/\\1/'; "
        + "grep -m1 '^default_mode' /etc/scx_loader.toml 2>/dev/null | sed 's/.*\"\\(.*\\)\".*/\\1/'; "
        + "pacman -Q gamemode >/dev/null 2>&1 && echo yes || echo no"]
      stdout: StdioCollector { onStreamFinished: {
        const l = this.text.split("\n"), m = (l[2] || "").match(/running (\w+) in (\w+) mode/), on = i => (l[i] || "").startsWith("enabled/active");
        root.tun = { scxChecked: true, repo: l[0] === "yes", v3: l[1] === "yes", scx: l[2] || "", sched: m ? m[1].toLowerCase() : "", mode: m ? m[2] : "",
                   ananicy: on(3), oomd: on(4), scxLoader: (l[5] || "").startsWith("enabled/"), ananicyPkg: l[6] === "yes", rulesPkg: l[7] === "yes", protonPkg: l[9] === "yes", dmem: (l[10] || "").startsWith("enabled/active"), bpftune: on(11), modes: (l[12] || "").split(/,\s*/).filter(x => x), defSched: l[13] || "", defMode: (l[14] || "").toLowerCase(), gamemodePkg: l[15] === "yes" }
      } }
    }
    Timer { id: tunTimer; interval: 1500; onTriggered: tunScan.running = true }
    property string tunBusy: ""   // the tweak being switched (installs the missing packages first)
    Process { id: tunRun; onExited: { root.tunBusy = ""; tunScan.running = true } }
    function tunTweak(key, on) { if (tunBusy) return; tunBusy = key; tunRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "tweak", on ? "on" : "off", key]; tunRun.running = true }
    function tunDmem(on) { if (tunBusy) return; tunBusy = "dmem"
      tunRun.command = on ? ["bash", "-c", "pacman -Q dmemcg-booster >/dev/null 2>&1 || pkexec /usr/local/libexec/lwts-priv pkg install dmemcg-booster; systemctl --user enable --now dmemcg-booster-user.service"]
                          : ["systemctl", "--user", "disable", "--now", "dmemcg-booster-user.service"]
      tunRun.running = true }
    function tunProton(on) { if (tunBusy) return; tunBusy = "proton"
      tunRun.command = ["pkexec", "/usr/local/libexec/lwts-priv", "pkg", on ? "install" : "remove", "proton-cachyos-slr"]
      tunRun.running = true }
    // StyledText: <b> titles, <br> breaks. Texts follow wiki.cachyos.org/configuration/sched-ext (read 2026-10-25), not our own benchmarks.
    readonly property string scxHint: "<b>Best for (CachyOS wiki)</b><br>"
      + "\u2022 <b>Bpfland</b>: gaming, desktop, audio; built around interactivity. A good start<br>"
      + "\u2022 <b>LAVD</b>: gaming, audio production, latency-sensitive work<br>"
      + "\u2022 <b>Flash</b>: gaming, audio and video, steady even when the CPU is overloaded<br>"
      + "\u2022 <b>Cosmos</b>: general purpose, adapts to desktop or server<br>"
      + "\u2022 <b>Flow</b>: desktop multitasking, gaming with background apps, development (only Auto)<br>"
      + "\u2022 <b>Rusty</b>: gaming and desktop too, but \"production ready if tuned correctly\"<br>"
      + "<br>The wiki: no scheduler fits everyone. Try a few and compare the FPS. Switching asks for the password."
    readonly property string goalHint: "<b>Max FPS</b>: LAVD, Gaming: steady frame rate in games<br>"
      + "<b>Lowest input lag</b>: Bpfland, Low latency: fastest reaction; the gain is small, the frame cap and VRR matter more<br>"
      + "<b>Game + apps at once</b>: Flow: a game with browser, chat, stream open<br>"
      + "<b>Quiet and cool</b>: Bpfland, Power save: less power and heat<br>"
      + "<b>Heavy work</b>: Bpfland, Server: rendering, compiling, long jobs<br>"
      + "<b>Balanced</b>: Bpfland, Auto: everything a bit<br>"
      + "<b>Off</b>: stops sched_ext; the kernel's own scheduler (BORE or EEVDF) runs. Handy to compare FPS<br>"
      + "<br>The picks follow the CachyOS wiki, not tests on your PC. Scheduler and Mode below are for fine-tuning. Switching asks for the password."
    readonly property string modeHint: "<b>Auto</b>: the scheduler's defaults (the Balanced power profile)<br>"
      + "<b>Gaming</b>: steady frame rate (the Performance power profile)<br>"
      + "<b>Low latency</b>: lower latency at the cost of throughput; aimed at audio and multimedia<br>"
      + "<b>Power save</b>: favors efficient cores, less power (the Power Saver profile)<br>"
      + "<b>Server</b>: throughput over responsiveness<br>"
      + "<br>The flags behind each mode differ per scheduler; with LAVD, Gaming and Low latency are the same. Some schedulers only have Auto here."

    function tunUnit(u, on) { Quickshell.execDetached(["pkexec", "/usr/local/libexec/lwts-priv", "service", on ? "enable-now" : "disable-now", u + ".service"]); tunTimer.restart() }
    property bool scxManual: false   // "Custom" picked: the Scheduler and Mode rows are shown
    function scxBootSave() { if (!tun.sched) return
      Quickshell.execDetached(["pkexec", "/usr/local/libexec/lwts-priv", "scx-boot", tun.sched, (tun.mode || "auto").toLowerCase()]); tunTimer.restart() }
    readonly property bool scxBootDiffers: !!tun.scxLoader && !!tun.sched && (tun.defSched !== tun.sched || tun.defMode !== (tun.mode || "").toLowerCase())
    function scxBoot(on) { Quickshell.execDetached(["pkexec", "/usr/local/libexec/lwts-priv", "service", on ? "enable" : "disable", "scx_loader.service"]); tunTimer.restart() }
    // presets for the "Preset" row: [id, label, scheduler, mode]; picks follow wiki.cachyos.org/configuration/sched-ext, not benchmarks
    readonly property var scxGoals: [["balanced", "Balanced", "bpfland", "auto"], ["fps", "Max FPS (steady frames)", "lavd", "gaming"],
      ["lag", "Lowest input lag", "bpfland", "lowlatency"], ["multi", "Game + apps at once", "flow", "auto"],
      ["quiet", "Quiet and cool", "bpfland", "powersave"], ["work", "Heavy work (render, compile)", "bpfland", "server"]]
    function scxGoalNow() { if (!tun.sched && tun.scx !== undefined && tun.scxChecked) return "off"; const g = scxGoals.find(x => x[2] === tun.sched && x[3] === (tun.mode || "").toLowerCase()); return g ? g[0] : "custom" }
    function scxGoalSet(id) { if (id === "off") { Quickshell.execDetached(["scxctl", "stop"]); tunTimer.restart(); return }
      const g = scxGoals.find(x => x[0] === id); if (g) { Quickshell.execDetached(["scxctl", tun.sched ? "switch" : "start", "--sched", g[2], "--mode", g[3]]); tunTimer.restart() } }
    function scxSwitch(arg, v) { Quickshell.execDetached(["scxctl", "switch", arg, v]); tunTimer.restart() }


  readonly property var gpuRows: [
    tab("GPU"),
    header("Tuning"),
    slider("GPU clock, min", "Lowest engine clock under load", span(Number(gpuInfo.lim_smin) || 500, Number(gpuInfo.lim_smax) || 2950, 50), "MHz", () => dv("smin"), v => setDraft("smin", v)),
    slider("GPU clock, max", "Highest engine clock", span(Number(gpuInfo.lim_smin) || 500, Number(gpuInfo.lim_smax) || 2950, 50), "MHz", () => dv("smax"), v => setDraft("smax", v)),
    slider("Memory clock", "VRAM; the driver allows up to " + gi("lim_mmax") + " MHz", span(Number(gpuInfo.lim_mmin) || 674, Number(gpuInfo.lim_mmax) || 1075, 25), "MHz", () => dv("mclk"), v => setDraft("mclk", v)),
    slider("Voltage offset", "Negative = cooler and quieter, too low = crashes", span(-200, 0, 5), "mV", () => dv("vo"), v => setDraft("vo", v)),
    slider("Power limit", "Allowed " + gi("lim_wmin") + " – " + gi("lim_wmax") + " W, driver default " + gi("cap_default") + " W", span(Number(gpuInfo.lim_wmin) || 198, Number(gpuInfo.lim_wmax) || 242, 1), "W", () => dv("cap"), v => setDraft("cap", v)),
    gpuCountdown > 0
      ? { type: "action", label: "Keep these settings?", desc: "Reverts by itself in " + gpuCountdown + " s", buttons: [["Keep", () => gpuKeep()], ["Revert", () => gpuRevert("Reverted")]] }
      : { type: "action", label: "Apply", desc: gpuMsg || "Writes the sliders to the card; you get 15 s to confirm, otherwise it goes back",
          buttons: [["Apply", () => gpuApplyDraft()], ["Save for boot", () => gpuRunCmd("persist", ["gpu-persist"].concat(vals({ smin: gpuInfo.smin, smax: gpuInfo.smax, mclk: gpuInfo.mclk, vo: gpuInfo.vo, cap: gpuInfo.cap })))],
                    ["Driver defaults", () => gpuRunCmd("reset", ["gpu-reset"])]] },
    info("Mode", gi("level"))
  ]

  readonly property var tuningRows: [
    tab("Tuning"), header("CachyOS repositories"),
    info("Status", tun.repo ? "Connected" : tun.v3 ? "Not connected" : "Not available (CPU has no x86-64-v3)"),
    header("Scheduler (sched_ext)"),
    info("Running", tun.scx || (tun.scxLoader === undefined ? "Checking…" : "Nothing running")),
    Object.assign(cycle("Preset", "Pick what you need; the scheduler and mode are set for you",
          [["off", "Off (kernel scheduler)"]].concat(scxGoals.map(g => [g[0], g[1]]), [["custom", "Custom"]]),
          () => scxManual ? "custom" : scxGoalNow(), v => { if (v === "custom") scxManual = true; else { scxManual = false; scxGoalSet(v) } }), { hint: goalHint }),
    ...(scxManual || scxGoalNow() === "custom" ? [
      Object.assign(cycle("Scheduler", "Switches at once; every scheduler is a different trade-off between FPS and responsiveness",
            [["bpfland", "Bpfland"], ["lavd", "LAVD"], ["rusty", "Rusty"], ["flash", "Flash"], ["cosmos", "Cosmos"], ["flow", "Flow"]],
            () => tun.sched || "bpfland", v => scxSwitch("--sched", v)), { hint: scxHint }),
      Object.assign(cycle("Mode", "Preset of the running scheduler; some schedulers (Flash, Rusty) only have Auto",
            (tun.modes && tun.modes.length ? tun.modes : ["Auto"]).map(m => [m.toLowerCase(), m === "LowLatency" ? "Low latency" : m === "PowerSave" ? "Power save" : m]),
            () => (tun.mode || "Auto").toLowerCase(), v => scxSwitch("--mode", v)), { hint: modeHint })] : []),
    choice("Keep at boot", tun.scxLoader ? "On: at boot " + (tun.defSched || "?") + " / " + (tun.defMode || "?") + " starts" : "Off: no sched_ext scheduler at boot (the kernel's own one)",
           [["off", "Off"], ["on", "On"]], () => tun.scxLoader ? "on" : "off", v => v === "on" ? scxBootSave() : scxBoot(false)),
    ...(scxBootDiffers ? [{ type: "action", label: "Boot default differs", desc: "Running: " + tun.sched + " / " + (tun.mode || "").toLowerCase() + "; at boot: " + tun.defSched + " / " + tun.defMode,
                            buttons: [["Save the running one", scxBootSave]] }] : []),
    header("Services"),
    choice("Process priorities (ananicy-cpp)", tunBusy === "ananicy" ? "Working…" : "Gives games and the desktop the CPU first. On: installs it and the CachyOS rules if missing; off: only stops the service" + (tun.gamemodePkg ? ". Warning: GameMode is installed too; both change process priorities and fight. Keep one" : ""),
           [["off", "Off"], ["on", "On"]], () => tun.ananicy ? "on" : "off", v => tunTweak("ananicy", v === "on")),
    choice("Out-of-memory killer (systemd-oomd)", "Kills the hungriest app before the system freezes; can close a game under memory pressure", [["off", "Off"], ["on", "On"]],
           () => tun.oomd ? "on" : "off", v => tunUnit("systemd-oomd", v === "on")),
    choice("VRAM priority (dmemcg-booster)", tunBusy === "dmem" ? "Working…" : "Keeps the game's video memory out of system RAM; in this session only games under gamescope can use it. On: installs it if missing",
           [["off", "Off"], ["on", "On"]], () => tun.dmem ? "on" : "off", v => tunDmem(v === "on")),
    choice("Proton CachyOS", tunBusy === "proton" ? "Working…" : "Proton build tuned for the CachyOS repository (Steam Linux Runtime). Pick it per game in Steam: Properties, Compatibility. Off: removes the package; games set to it need another Proton",
           [["off", "Off"], ["on", "On"]], () => tun.protonPkg ? "on" : "off", v => tunProton(v === "on")),
    choice("Network auto-tuning (bpftune)", tunBusy === "bpftune" ? "Working…" : "Tunes TCP and other network settings on the fly (experimental). On: installs bpftune-git from the CachyOS repository if missing",
           [["off", "Off"], ["on", "On"]], () => tun.bpftune ? "on" : "off", v => tunTweak("bpftune", v === "on"))
  ]

  property var extra: ({ gaming: (amdGpu ? gpuRows : []).concat(tuningRows), power: liteRows })
  readonly property var liteRows: [].concat(
      [tab("Lite mode"), header("Lite mode"),
       info("Now", Session.game ? "On" : "Off"),
       { type: "action", label: "Right now", desc: "The same as the Lite tile in Quick settings",
         buttons: [[Session.game ? "Turn off" : "Turn on", () => Session.toggleGame()]] },
       header("What Lite turns off"),
       choice("Level", "Light: animations, blur, rounding. Medium: also transparency, bar margins, night light. Max: also lock / sleep and power saving",
              [["light", "Light"], ["medium", "Medium"], ["max", "Max"], ["custom", "Custom"]], () => liteCustom || liteLevel() === "" ? "custom" : liteLevel(), v => liteSet(v))]
        .concat(liteCustom || liteLevel() === "" ? [multi("Custom", "", [["game_animations", "Animations"], ["game_blur", "Blur"], ["game_rounding", "Rounding"],
                    ["game_transparency", "Transparency"], ["game_nightlight", "Night light"], ["game_bar_margins", "Bar margins"],
                    ["game_idle", "Lock / sleep"], ["game_power", "Power saving"]], id => liteOn(id), id => Prefs.set(id, !liteOn(id)))] : [],
          laptop ? [cycle("Lite on battery below", "Turns on by itself, off when charging", [[0, "Never"], [10, "10%"], [15, "15%"], [20, "20%"], [30, "30%"]],
                      () => Number(Prefs.get("lite_battery", 0)), v => Prefs.set("lite_battery", v))] : [])
  )
  property bool amdGpu: false   // GPU clocks / voltage only exist on AMD cards (the desktop)
  FileView { path: "/sys/class/drm/card0/device/vendor"; printErrors: false; onLoaded: if (text().trim() === "0x1002") root.amdGpu = true }
  FileView { path: "/sys/class/drm/card1/device/vendor"; printErrors: false; onLoaded: if (text().trim() === "0x1002") root.amdGpu = true }

  property var rows: [].concat(
      [tab("Overlay"), header("Overlay"),   // MangoHud
       choice("Position", "Corner of the screen", [["top-left", "Top left"], ["top-right", "Top right"], ["bottom-left", "Bottom left"], ["bottom-right", "Bottom right"]],
              () => Prefs.get("mango_pos", "top-left"), v => mangoSet("mango_pos", v)),
       choice("Quick pick", "Ready sets of metrics; the lists below fine-tune them", [["fps", "FPS"], ["basic", "Basic"], ["full", "Full"]],
              () => mangoPresetNow(), v => mangoSet("mango_metrics", mangoPresets[v]))],
      [].concat(...mangoGroups.map(g => multi(g[0], "", g[1], id => mangoMetrics().indexOf(id) >= 0, id => mangoToggle(id)))),
      [header("My presets")].concat(mangoPresetList().map(x => ({ type: "action", label: x.split("|")[0],
          desc: x.split("|")[1].split(",").filter(i => i).length + " items", buttons: [["Use", () => mangoUsePreset(x)], ["Delete", () => mangoDelPreset(x.split("|")[0])]] })), [
       input("Save current as", "Keeps the switches above under a name; the same name replaces it (up to 8)", () => "", v => mangoSavePreset(v.trim()),
             { placeholder: "name", validate: t => !/^[A-Za-z0-9А-Яа-яІіЇїЄєҐґ _-]{1,20}$/.test(t.trim()) ? "1-20 letters, digits, space, - _"
                 : mangoPresetList().length >= 8 && !mangoPresetList().some(x => x.split("|")[0] === t.trim()) ? "8 presets is the limit" : "" }),
       choice("Switch in the game", "On: the key below walks through my presets; Off: the switches above are used as they are", [["off", "Off"], ["on", "On"]],
              () => Prefs.get("mango_cycle", "off") === "on" || Prefs.get("mango_cycle", "off") === true ? "on" : "off", v => mangoSet("mango_cycle", v)),
       cycle("Next preset", "", mangoKeys([["Shift_R+F10", "Right Shift + F10"], ["Shift_L+F10", "Left Shift + F10"], ["Control_L+F10", "Ctrl + F10"]]),
             () => Prefs.get("mango_bind_preset", ""), v => mangoSet("mango_bind_preset", v))]),
      [header("FPS limit"),
       choice("Starting cap", "Applied when a game starts; the key below steps through the list", [["0", "Off"], ["60", "60"], ["120", "120"], ["144", "144"]],
              () => String(Prefs.get("mango_fps_limit", "0")), v => mangoSet("mango_fps_limit", v)),
       choice("Limiter", "Early: waits before drawing, less input lag. Late: waits after, steadier frame pacing", [["early", "Early"], ["late", "Late"]],
              () => Prefs.get("mango_limit_method", "late"), v => mangoSet("mango_limit_method", v))],
      [header("Keys in a game"),
       cycle("Show / hide overlay", "Applies on the next game launch", mangoKeys([["Shift_R+F12", "Right Shift + F12"], ["Shift_L+F12", "Left Shift + F12"], ["Control_L+F12", "Ctrl + F12"]]),
             () => Prefs.get("mango_bind_hud", ""), v => mangoSet("mango_bind_hud", v)),
       cycle("Next FPS cap", "", mangoKeys([["Shift_R+F11", "Right Shift + F11"], ["Shift_R+F9", "Right Shift + F9"], ["Shift_L+F11", "Left Shift + F11"], ["Control_L+F11", "Ctrl + F11"]]),
             () => Prefs.get("mango_bind_limit", ""), v => mangoSet("mango_bind_limit", v)),
       cycle("Record a log", "", mangoKeys([["Shift_L+F2", "Left Shift + F2"], ["Shift_R+F2", "Right Shift + F2"], ["Control_L+F2", "Ctrl + F2"]]),
             () => Prefs.get("mango_bind_log", ""), v => mangoSet("mango_bind_log", v))],
      [header("Style"),
       slider("Font size", "Overlay text", [14, 16, 18, 20, 24, 28], "px",
              () => Number(Prefs.get("mango_font", 20)), v => mangoSet("mango_font", v)),
       Object.assign(slider("Backdrop", "Opacity of the plate behind the text", [0, 0.25, 0.45, 0.65, 0.85], "",
              () => Number(Prefs.get("mango_alpha", 0.45)), v => mangoSet("mango_alpha", v)), { format: v => Math.round(v * 100) + "%" })],
      [tab("Launch options"), header("When a game starts"),
       choice("Lite mode while playing", "Turns Lite on when a Steam game window opens and off when the last one closes (set what Lite does in Power -> Lite mode)",
              [["off", "Off"], ["on", "On"]], () => Prefs.get("game_auto", false) === true ? "on" : "off", v => Prefs.set("game_auto", v === "on")),
       header("All games"),
       info("Applies to", "Every Steam game started from Steam, and any game run with lwts-game")]
        .concat(envGroupRows("global", envGlobal),
          envRows("global", envGlobal, true),
          [input("Add a variable", envMsg || "NAME=value; new games pick it up when they start", () => "", v => envAdd("global", v), { placeholder: "NAME=value", validate: envCheck })]),
      [header("One game"),
       cycle("Game", "Installed Steam games", [["", "Choose…"]].concat(envGames.map(g => [g[0], g[1]])), () => envApp, v => { envApp = String(v) })]
        .concat(envApp ? envGroupRows(envApp, envOwn).concat(envRows(envApp, envOwn, true), [
          input("Add a variable", "Only for this game; wins over the ones above", () => "", v => envAdd(envApp, v), { placeholder: "NAME=value", validate: envCheck }),
          { type: "action", label: "Steam launch options", desc: "Paste into the game's Properties → Launch options: lwts-game %command%",
            buttons: [["Copy", () => Quickshell.execDetached(["bash", "-c", "printf %s 'lwts-game %command%' | wl-copy"])]] }]) : [])
  )
}
