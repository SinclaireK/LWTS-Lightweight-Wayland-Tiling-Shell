// The "Printers" tab of Settings -> Devices (moved from settings/SettingsNew.qml): CUPS through lpstat / lpadmin / lp / cancel.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

Scope {
  id: root
  property string section: "devices"
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  function info(label, value) { return { type: "info", label, value } }
  property var printers: []        // [{ name, state }]
  property string printerDefault: ""
  property var printJobs: []       // [{ id, text }]
  property string cupsState: "?"   // ? | missing | stopped | running
  property string printMsg: ""
  property var printFound: []      // [{ uri, name }]
  Process {
    id: cupsScan
    command: ["bash", "-c", 'if ! command -v cupsd >/dev/null && [ ! -x /usr/sbin/cupsd ]; then echo STATE missing; exit; fi; '
      + 'if ! systemctl is-active --quiet cups; then echo STATE stopped; exit; fi; echo STATE running; lpstat -p -d 2>/dev/null; echo JOBS; lpstat -o 2>/dev/null']
    stdout: StdioCollector { onStreamFinished: {
      const t = this.text.split("\n"), pr = [], jobs = []; let inJobs = false;
      root.printerDefault = "";
      for (const l of t) {
        if (l.startsWith("STATE ")) root.cupsState = l.slice(6);
        else if (l === "JOBS") inJobs = true;
        else if (inJobs && l.trim()) jobs.push({ id: l.split(" ")[0], text: l.trim() });
        else if (l.startsWith("printer ")) { const m = l.match(/^printer (\S+) (.*)$/); if (m) pr.push({ name: m[1], state: m[2].replace(/\.$/, "").replace(/\s+since.*$/, "") }) }
        else if (l.startsWith("system default destination: ")) root.printerDefault = l.slice(28).trim();
      }
      root.printers = pr; root.printJobs = jobs;
    } }
  }
  Process { id: printRun; onExited: { cupsScan.running = true } }
  function printCmd(args) { printRun.command = args; printRun.running = true }
  Process {
    id: printFind
    command: ["bash", "-c", "lpinfo -v 2>/dev/null | grep -E '^network (ipp|dnssd|socket|lpd)' | head -20"]
    stdout: StdioCollector { onStreamFinished: { root.printFound = this.text.trim().split("\n").filter(l => l).map(l => { const u = l.replace(/^network /, ""); return { uri: u, name: decodeURIComponent(u.replace(/^[a-z]+:\/\//, "").split("._")[0]) } }); root.printMsg = root.printFound.length ? "" : "Nothing found on the network" } }
  }
  Connections { target: Modules; function onOpenSectionChanged() { if (Modules.openSection === "devices") cupsScan.running = true } }
  function printerRows() {
    const T = { missing: "Not installed", stopped: "Installed, not running", running: "Running", "?": "Checking…" };
    const rows = [info("Printing service (CUPS)", T[cupsState] || cupsState)];
    if (cupsState === "missing")
      return rows.concat([{ type: "action", label: "Install printing support", desc: "Opens a terminal; pacman asks you to confirm", buttons: [["Install", () => Quickshell.execDetached(["alacritty", "-e", "sh", "-c", "sudo pacman -S cups cups-filters; echo; read -p 'Press Enter to close' x"])]] }]);
    if (cupsState === "stopped")
      return rows.concat([{ type: "action", label: "Start the service", desc: "Starts now and at every boot", buttons: [["Start", () => printCmd(["bash", "-c", "pkexec /usr/local/libexec/lwts-priv service enable cups.service && pkexec /usr/local/libexec/lwts-priv service start cups.service"])]] }]);
    if (cupsState !== "running") return rows;
    rows.push(header("Printers"));
    if (!printers.length) rows.push(info("Printers", "None added yet"));
    for (const p of printers)
      rows.push({ type: "action", label: p.name, desc: p.state + (p.name === printerDefault ? " · default" : ""),
        buttons: [].concat(p.name === printerDefault ? [] : [["Make default", () => printCmd(["lpoptions", "-d", p.name])]],
                           [["Test page", () => printCmd(["lp", "-d", p.name, "/usr/share/cups/data/testprint"])], ["Remove", () => printCmd(["pkexec", "lpadmin", "-x", p.name])]]) });
    rows.push(header("Add a printer"));
    rows.push({ type: "action", label: "Look on the network", desc: printMsg || "Finds printers that announce themselves", buttons: [["Search", () => { printMsg = "Searching…"; printFound = []; printFind.running = true }]] });
    for (const f of printFound)
      rows.push({ type: "action", label: f.name, desc: f.uri, buttons: [["Add", () => printCmd(["pkexec", "lpadmin", "-p", f.name.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 40), "-E", "-v", f.uri, "-m", "everywhere"])]] });
    if (printJobs.length) {
      rows.push(header("Print queue"));
      for (const j of printJobs) rows.push({ type: "action", label: j.id, desc: j.text, buttons: [["Cancel", () => printCmd(["cancel", j.id])]] });
    }
    return rows;
  }
  property var rows: [tab("Printers")].concat(printerRows())
}
