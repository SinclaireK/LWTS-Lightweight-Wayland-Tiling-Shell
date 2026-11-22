// Details Quickshell.Networking does not give: IP, gateway, link speed of a device (nmcli + /sys), on request.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property var info: ({})   // { ip, gw, speed }
  function load(dev) { proc.command = ["sh", "-c", "nmcli -g IP4.ADDRESS,IP4.GATEWAY dev show " + dev + "; cat /sys/class/net/" + dev + "/speed 2>/dev/null"]; proc.running = true }
  function copy(t) { Quickshell.execDetached(["wl-copy", t]) }
  Process {
    id: proc
    stdout: StdioCollector { onStreamFinished: { const l = text.trim().split("\n"); root.info = { ip: (l[0] || "").replace(/\/\d+$/, "").split(" | ")[0], gw: l[1] || "", speed: l[2] ? l[2] + " Mb/s" : "" } } }
  }

  // ---- speed test: Cloudflare over curl + ping (nothing to install). Stages: ping (RTT, jitter, loss) -> download with 4 streams while pinging
  // (loaded latency) -> upload the same way. ~20 s, ~400 MB down / up to ~240 MB up. The live load is the interface meter of the panel.
  property var speed: ({})       // { ping, jitter (ms), loss (%), down, up (Mbit/s), ldown, lup (ms under load), at (ms) } or { failed }
  property string phase: ""      // "" | ping | down | up
  readonly property bool testing: speedProc.running
  function speedTest() { if (!speedProc.running) { cur = {}; phase = "ping"; speedProc.running = true } }
  property var cur: ({})
  function rtt(l) { const m = l.match(/= ([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+)/); return m ? { avg: Number(m[2]), mdev: Number(m[4]) } : null }
  function sumMbit(l) {   // "down 123+456+...+0 8012" = bytes of the streams (a sum) and the elapsed ms
    const a = l.trim().split(/\s+/), ms = Number(a[2]) || 0, bytes = (a[1] || "").split("+").reduce((x, y) => x + (Number(y) || 0), 0);
    return ms > 0 ? bytes * 8 / 1e6 / (ms / 1000) : 0
  }
  Process {
    id: speedProc
    command: ["sh", "-c", `t=$(mktemp -d); u=https://speed.cloudflare.com; h=1.1.1.1; w=8
      echo phase ping; ping -c 10 -i 0.2 -q $h | tail -2
      echo phase down; ping -c 8 -i 1 -q $h > $t/ld &
      t0=$(date +%s%N); end=$(( $(date +%s) + w ))
      for i in 1 2 3 4; do ( b=0; while [ $(date +%s) -lt $end ]; do n=$(curl -so /dev/null -m 8 -w "%{size_download}" "$u/__down?bytes=5000000"); b=$((b+\${n:-0})); done; echo $b > $t/d$i ) & done; wait
      echo down $(cat $t/d? | tr '\n' '+')0 $(( ($(date +%s%N) - t0) / 1000000 )); echo ldown $(tail -1 $t/ld)
      echo phase up; ping -c 8 -i 1 -q $h > $t/lu &
      t0=$(date +%s%N); end=$(( $(date +%s) + w ))
      for i in 1 2 3 4; do ( b=0; while [ $(date +%s) -lt $end ]; do n=$(head -c 5000000 /dev/zero | curl -so /dev/null -m 8 -w "%{size_upload}" --data-binary @- "$u/__up"); b=$((b+\${n:-0})); done; echo $b > $t/u$i ) & done; wait
      echo up $(cat $t/u? | tr '\n' '+')0 $(( ($(date +%s%N) - t0) / 1000000 )); echo lup $(tail -1 $t/lu)
      echo done; rm -rf $t`]
    stdout: SplitParser { onRead: l => {
      const c = root.cur;
      if (l.startsWith("phase ")) root.phase = l.slice(6);
      else if (l.includes("packet loss")) { const m = l.match(/([\d.]+)% packet loss/); if (m) c.loss = Number(m[1]) }
      else if (l.startsWith("rtt ")) { const r = root.rtt(l); if (r) { c.ping = r.avg; c.jitter = r.mdev } }
      else if (l.startsWith("down ")) c.down = root.sumMbit(l);
      else if (l.startsWith("up ")) c.up = root.sumMbit(l);
      else if (l.startsWith("ldown ")) { const r = root.rtt(l); if (r) c.ldown = r.avg }
      else if (l.startsWith("lup ")) { const r = root.rtt(l); if (r) c.lup = r.avg }
      else if (l === "done") root.speed = c.down > 0 ? Object.assign({ at: Date.now() }, c) : { failed: true };
    } }
    onExited: { root.phase = ""; if (!root.speed.at && !root.speed.failed) root.speed = { failed: true } }
  }

  // ---- public IP + provider (ipinfo.io, Cloudflare trace as the fallback; once per 10 min, only when the Network tab asks)
  property var pub: ({})         // { ip, isp, at }
  function loadPublic() { if (!pubProc.running && (!pub.at || Date.now() - pub.at > 600000)) pubProc.running = true }
  Process {
    id: pubProc; command: ["sh", "-c", "curl -sf -m 5 https://ipinfo.io/json || curl -s -m 5 https://1.1.1.1/cdn-cgi/trace"]
    stdout: StdioCollector { onStreamFinished: {
      let ip = "", isp = "";
      try { const j = JSON.parse(text); ip = j.ip || ""; isp = (j.org || "").replace(/^AS\d+\s+/, "").replace(/"/g, "") } catch (e) {
        ip = (text.match(/^ip=(.+)$/m) || [0, ""])[1] }
      if (ip) root.pub = { ip: ip, isp: isp, at: Date.now() };
    } }
  }
  property var dns: ({ servers: [], conn: "", auto: true })   // servers in use, the NetworkManager connection, ignore-auto-dns off
  function loadDns(dev) { dnsDev = dev; dnsProc.command = ["sh", "-c", "nmcli -g IP4.DNS dev show " + dev + "; nmcli -g GENERAL.CONNECTION dev show " + dev]; dnsProc.running = true }
  property string dnsDev: ""
  Process {
    id: dnsProc
    stdout: StdioCollector { onStreamFinished: {
      const l = text.split("\n"); const conn = (l[1] || "").trim();
      root.dns = { servers: (l[0] || "").split("|").map(x => x.trim()).filter(x => x), conn: conn, auto: root.dns.auto };
      if (conn) { ignP.command = ["nmcli", "-g", "ipv4.ignore-auto-dns", "connection", "show", conn]; ignP.running = true }
    } }
  }
  Process { id: ignP; stdout: StdioCollector { onStreamFinished: root.dns = { servers: root.dns.servers, conn: root.dns.conn, auto: text.trim() !== "yes" } } }
  // servers = "" -> back to the router's DNS; otherwise a space separated list of IPv4 addresses (the panel's presets only)
  property bool dnsBusy: dnsMod.running || dnsApply.running
  function setDns(servers) {
    if (!dns.conn || !dnsDev || dnsBusy) return;
    dnsMod.command = ["nmcli", "connection", "modify", dns.conn, "ipv4.dns", servers, "ipv4.ignore-auto-dns", servers === "" ? "no" : "yes"]; dnsMod.running = true
  }
  Process { id: dnsMod; onExited: code => { if (code === 0) { dnsApply.command = ["nmcli", "device", "reapply", root.dnsDev]; dnsApply.running = true } } }
  Process { id: dnsApply; onExited: root.loadDns(root.dnsDev) }
  // ---- connection settings (NetworkManager profile of the active device): auto-connect, metered, IPv6; reconnect
  property var cset: ({ auto: true, metered: false, v6: true })
  function loadSet() { if (dns.conn && !setR.running) { setR.command = ["nmcli", "-g", "connection.autoconnect,connection.metered,ipv6.method", "connection", "show", dns.conn]; setR.running = true } }
  Process {
    id: setR
    stdout: StdioCollector { onStreamFinished: { const l = text.split("\n"); root.cset = { auto: (l[0] || "").trim() !== "no", metered: (l[1] || "").trim() === "yes", v6: ["auto", "dhcp", ""].includes((l[2] || "").trim()) } } }
  }
  function setProp(prop, val) {   // live apply where NM can (reapply), otherwise it takes effect on the next connect
    if (!dns.conn || dnsBusy) return;
    dnsMod.command = ["nmcli", "connection", "modify", dns.conn, prop, val]; dnsMod.running = true
  }
  function reconnect() { if (dns.conn) { rcP.command = ["sh", "-c", "nmcli connection down \"$0\"; nmcli connection up \"$0\"", dns.conn]; rcP.running = true } }
  Process { id: rcP; onExited: root.loadDns(root.dnsDev) }
}
