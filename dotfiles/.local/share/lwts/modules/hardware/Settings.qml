// Sound -> "ALSA mixer" tab and System -> "Format" tab (removable drives only).
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "sound"
  function tab(label) { return { type: "tab", label } }
  function header(label) { return { type: "header", label } }
  function info(label, value) { return { type: "info", label, value } }
  function choice(label, desc, options, get, set) { return { type: "choice", label, desc, options, get, set } }
  function cycle(label, desc, options, get, set) { return { type: "cycle", label, desc, options, get, set } }
  function slider(label, desc, get, set) { return { type: "slider", label, desc, steps: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], unit: "%", get, set } }
  function action(label, desc, buttons) { return { type: "action", label, desc, buttons } }
  function input(label, desc, get, set, o) { return Object.assign({ type: "input", label, desc, get, set }, o || {}) }

  function mixerRows() {
    const out = [tab("ALSA mixer"), header("Card"),
      cycle("Sound card", "Every control of the card, as alsamixer shows it", Hw.cards.map(c => [c.n, c.name]), () => Hw.card, v => Hw.pickCard(Number(v)))];
    if (!Hw.controls.length) return out.concat([info("Controls", !Hw.hasAmixer ? "Needs alsa-utils: sudo pacman -S alsa-utils" : "None on this card")]);
    out.push(header("Controls"));
    for (const c of Hw.controls) {
      const n = c.name + (c.idx ? " " + c.idx : "");
      if (c.pvol >= 0) out.push(slider(n, c.psw === null ? "" : "Playback", () => Hw.controls.find(x => x.name === c.name && x.idx === c.idx).pvol, v => Hw.setVol(c, false, v)));
      if (c.psw !== null) out.push(choice(c.pvol >= 0 ? n + " · on" : n, "", [["on", "On"], ["off", "Off"]], () => Hw.controls.find(x => x.name === c.name && x.idx === c.idx).psw ? "on" : "off", v => Hw.setSw(c, false, v === "on")));
      if (c.cvol >= 0) out.push(slider(n + " · capture", "", () => Hw.controls.find(x => x.name === c.name && x.idx === c.idx).cvol, v => Hw.setVol(c, true, v)));
      if (c.csw !== null) out.push(choice(n + " · capture on", "", [["on", "On"], ["off", "Off"]], () => Hw.controls.find(x => x.name === c.name && x.idx === c.idx).csw ? "on" : "off", v => Hw.setSw(c, true, v === "on")));
      if (c.items.length) out.push(cycle(n, "", c.items.map(i => [i, i]), () => Hw.controls.find(x => x.name === c.name && x.idx === c.idx).item, v => Hw.setItem(c, v)));
    }
    return out;
  }

  function formatRows() {
    const out = [tab("Format"), header("Removable drives")];
    if (!Hw.drives.length) out.push(info("Removable drives", "None plugged in · fixed and system disks are never listed"));
    for (const d of Hw.drives) {
      out.push(action(d.model + " · " + d.size, d.path + " · whole drive: new partition table + one partition", [["Format…", () => Hw.pick(d.path)]]));
      for (const p of d.parts)
        out.push(action("    " + p.path + " · " + p.size, p.fstype + (p.label ? " · " + p.label : "") + (p.mounts.length ? " · " + p.mounts.join(", ") : " · not mounted"), [["Format…", () => Hw.pick(p.path)]]));
    }
    if (Hw.target) out.push(header("Format " + Hw.target),
      cycle("File system", "", Hw.fsList, () => Hw.fs, v => Hw.fs = v),
      input("Label", "Optional name of the drive", () => Hw.label, v => Hw.label = v, { placeholder: "USB" }),
      action(Hw.armed ? "Press Erase again" : "Erase", "Everything on " + Hw.target + " is lost. Unmounts it first; asks for your password",
             [["Cancel", () => Hw.cancel()], [Hw.armed ? "Erase now" : "Erase", () => Hw.erase()]]));
    if (Hw.busy) out.push(info("Status", Hw.busy));
    else if (Hw.result) out.push(info("Status", Hw.result));
    return out;
  }

  property var rows: mixerRows()
  property var extra: ({ system: formatRows() })
}
