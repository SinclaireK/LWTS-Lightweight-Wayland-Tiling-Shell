// Hardware (advanced): the ALSA mixer of one sound card (amixer; live while Settings -> Sound is open, via `alsactl monitor`)
// and formatting of REMOVABLE drives only (USB sticks, SD cards) through UDisks2 over D-Bus: polkit asks for the password,
// nothing runs as root here. Fixed and system disks never show up as targets.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Singleton {
  id: root

  // ---------------- ALSA mixer ----------------
  property var cards: []        // [{ n, id, name }]
  property int card: -1         // chosen card number (Prefs "alsa_card"; default: the first non-HDMI one)
  property bool hasAmixer: true
  property var controls: []     // [{ name, idx, caps:[], pvol, cvol, psw, csw, items:[], item }]
  readonly property bool soundOpen: Modules.openSection === "sound"
  onSoundOpenChanged: if (soundOpen) { cardsProc.running = true; amixCheck.running = true }
  Process { id: amixCheck; command: ["sh", "-c", "command -v amixer"]; onExited: code => root.hasAmixer = code === 0 }

  function amix(args) { setProc.command = ["amixer", "-q", "-c", String(card)].concat(args); setProc.running = true }
  function ctl(c) { return c.name + "," + c.idx }
  function setVol(c, capture, pct) { amix(["sset", ctl(c), pct + "%"].concat(capture ? ["capture"] : [])) }
  function setSw(c, capture, on) { amix(["sset", ctl(c), capture ? (on ? "cap" : "nocap") : (on ? "unmute" : "mute")]) }
  function setItem(c, it) { amix(["sset", ctl(c), it]) }
  function pickCard(n) { card = n; Prefs.set("alsa_card", n); readProc.running = true }

  Process {
    id: cardsProc
    command: ["cat", "/proc/asound/cards"]
    stdout: StdioCollector { onStreamFinished: {
      const out = [];
      for (const l of text.split("\n")) { const m = l.match(/^\s*(\d+)\s+\[(\S+)\s*\]:\s*(.*?)\s+-\s+(.*)$/); if (m) out.push({ n: Number(m[1]), id: m[2], drv: m[3], name: m[4] }) }
      root.cards = out;
      const saved = Number(Prefs.get("alsa_card", -1));
      root.card = out.some(c => c.n === saved) ? saved : (out.find(c => !/hdmi/i.test(c.id + c.name) && !/usb/i.test(c.drv)) || out.find(c => !/hdmi/i.test(c.id + c.name)) || out[0] || { n: -1 }).n;
      if (root.card >= 0) readProc.running = true;
    } }
  }
  Process {
    id: readProc
    command: ["amixer", "-c", String(root.card), "scontents"]
    stdout: StdioCollector { onStreamFinished: {
      const out = []; let c = null;
      for (const l of text.split("\n")) {
        let m = l.match(/^Simple mixer control '(.*)',(\d+)$/);
        if (m) { c = { name: m[1], idx: Number(m[2]), caps: [], pvol: -1, cvol: -1, psw: null, csw: null, items: [], item: "" }; out.push(c); continue }
        if (!c) continue;
        if ((m = l.match(/^\s+Capabilities:\s*(.*)$/))) { c.caps = m[1].split(/\s+/); continue }
        if ((m = l.match(/^\s+Items:\s*(.*)$/))) { c.items = (m[1].match(/'[^']*'/g) || []).map(s => s.slice(1, -1)); continue }
        if ((m = l.match(/^\s+Item0:\s*'(.*)'/))) { c.item = m[1]; continue }
        // first channel line only: "Front Left: Playback 87 [100%] [0.00dB] [on]" / "Mono: Capture 30 [50%] [on]"
        if ((m = l.match(/^\s+[\w ]+:\s+(Playback|Capture)\s+-?\d+\s+\[(\d+)%\](.*)$/))) {
          const cap = m[1] === "Capture", sw = (m[3].match(/\[(on|off)\]/) || [])[1];
          if (cap ? c.cvol < 0 : c.pvol < 0) { if (cap) c.cvol = Number(m[2]); else c.pvol = Number(m[2]) }
          if (sw && (cap ? c.csw === null : c.psw === null)) { if (cap) c.csw = sw === "on"; else c.psw = sw === "on" }
          continue;
        }
        if ((m = l.match(/^\s+[\w ]+:\s+(Playback|Capture)\s+\[(on|off)\]/))) { if (m[1] === "Capture") { if (c.csw === null) c.csw = m[2] === "on" } else if (c.psw === null) c.psw = m[2] === "on" }
      }
      root.controls = out;
    } }
  }
  Process { id: setProc; onExited: readProc.running = true }
  Process {   // ALSA change events (other mixers, hotkeys) while Sound is open: re-read, debounced
    command: ["alsactl", "monitor", String(root.card)]
    running: root.soundOpen && root.card >= 0
    stdout: SplitParser { onRead: _ => reread.restart() }
  }
  Timer { id: reread; interval: 150; onTriggered: readProc.running = true }

  // ---------------- removable drives ----------------
  property var drives: []       // [{ path, name, model, size, parts: [{ path, name, size, fstype, label, mounts }] }]
  property string target: ""    // device path picked for formatting
  property string fs: "exfat"
  property string label: ""
  property bool armed: false    // "Erase" pressed once
  property string busy: ""      // status text while working
  property string result: ""
  property var fsTools: ({})    // fstype -> mkfs present
  readonly property bool systemOpen: Modules.openSection === "storage"
  onSystemOpenChanged: if (systemOpen) { lsProc.running = true; toolsProc.running = true }
  readonly property var fsList: [["exfat", "exFAT · any OS"], ["vfat", "FAT32 · old devices"], ["ext4", "ext4 · Linux"], ["btrfs", "btrfs · Linux"], ["ntfs", "NTFS · Windows"]]
    .filter(f => fsTools[f[0]])

  function sizeStr(b) { const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0; b = Number(b); while (b >= 1000 && i < 4) { b /= 1000; i++ } return (i ? b.toFixed(1) : b) + " " + u[i] }
  function pick(path) { target = path; armed = false; result = ""; label = ""; if (!fsTools[fs]) fs = (fsList[0] || ["exfat"])[0] }
  function cancel() { target = ""; armed = false }
  function erase() {
    if (!target || busy) return;
    if (!armed) { armed = true; disarm.restart(); return }
    armed = false;
    const whole = drives.some(d => d.path === target), dev = target.replace("/dev/", "");
    const lbl = label.replace(/'/g, "");
    // unmount everything on the target, then: a partition is formatted in place; a whole drive gets a fresh GPT + one partition
    const umount = "for p in $(lsblk -nro PATH,MOUNTPOINTS '" + target + "' | awk '$2!=\"\"{print $1}'); do udisksctl unmount -b \"$p\" || exit 1; done; ";
    const call = (obj, iface, args) => "gdbus call --system --dest org.freedesktop.UDisks2 --object-path /org/freedesktop/UDisks2/" + obj + " --method org.freedesktop.UDisks2." + iface + " " + args;
    const opts = "\"{'label': <'" + lbl + "'>, 'update-partition-type': <true>}\"";
    const cmd = whole
      ? umount + call("block_devices/" + dev, "Block.Format", "gpt \"{}\"") + " >/dev/null && " +
        call("block_devices/" + dev, "PartitionTable.CreatePartitionAndFormat", "0 0 '' '' \"{}\" " + fs + " \"{'label': <'" + lbl + "'>}\"")
      : umount + call("block_devices/" + dev, "Block.Format", fs + " " + opts);
    busy = "Formatting " + target + "…"; result = "";
    fmtProc.command = ["bash", "-c", cmd + " >/dev/null"]; fmtProc.running = true;
  }
  Timer { id: disarm; interval: 4000; onTriggered: root.armed = false }

  Process {
    id: lsProc
    command: ["lsblk", "-J", "-b", "-o", "PATH,NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS,RM,HOTPLUG,MODEL,TRAN"]
    stdout: StdioCollector { onStreamFinished: {
      let j = []; try { j = JSON.parse(text).blockdevices } catch (e) {}
      const sys = /^(\/|\/boot.*|\/home|\/efi|\/var.*|\/usr|\/mnt(\/.*)?|\[SWAP\])$/;
      const mounts = d => (d.mountpoints || []).filter(m => m);
      const anySys = d => mounts(d).some(m => sys.test(m)) || (d.children || []).some(anySys);
      root.drives = j.filter(d => d.type === "disk" && (d.rm || d.hotplug) && d.tran !== "nvme" && !anySys(d)).map(d => ({
        path: d.path, name: d.name, model: (d.model || "").trim() || "Drive", size: root.sizeStr(d.size),
        parts: (d.children || []).filter(p => p.type === "part").map(p => ({ path: p.path, name: p.name, size: root.sizeStr(p.size), fstype: p.fstype || "-", label: p.label || "", mounts: mounts(p) }))
      }));
      if (root.target && !root.drives.some(d => d.path === root.target || d.parts.some(p => p.path === root.target))) root.cancel();
    } }
  }
  Process {
    id: toolsProc
    command: ["bash", "-c", "for f in exfat vfat ext4 btrfs ntfs; do command -v mkfs.$f >/dev/null && echo $f; done"]
    stdout: StdioCollector { onStreamFinished: { const t = {}; for (const f of text.split("\n")) if (f) t[f] = true; root.fsTools = t } }
  }
  Process {
    id: fmtProc
    stderr: StdioCollector { id: fmtErr }
    onExited: code => { root.busy = ""; root.result = code === 0 ? "Done: " + root.target + " is " + root.fs : "Failed: " + (fmtErr.text.trim().split("\n").pop() || "exit " + code); if (code === 0) root.target = ""; lsProc.running = true }
  }
  Process {   // drives plugged / removed while System is open
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
    running: root.systemOpen
    stdout: SplitParser { onRead: _ => relist.restart() }
  }
  Timer { id: relist; interval: 800; onTriggered: lsProc.running = true }
}
