import QtQuick
import Quickshell.Services.UPower
import qs.services
QtObject {
  // peripherals with a battery (mouse, gamepad, headset ...): UPower, not the laptop battery / the display summary
  function peri() { return UPower.devices.values.filter(d => d.ready && !d.isLaptopBattery && d !== UPower.displayDevice && d.isPresent !== false) }
  function batText() { const l = peri(); return l.length ? l.map(d => (d.model || "Device").split(" ").slice(0, 2).join(" ") + " " + Math.round(d.percentage * 100) + "%").join(" · ") : "No devices" }
  property var defs: ({
    picker:    { icon: "eyedropper", label: () => "Color", status: () => Tools.color, on: () => false, act: () => Tools.pick(), toggleless: true },
    ocr:       { icon: "scan", label: () => "Text", toggleless: true, on: () => false, act: () => Tools.ocr(),
                 status: () => ({ busy: "Reading…", copied: "Copied", empty: "Nothing found", missing: "Needs tesseract" })[Tools.ocrState] || "" },
    batteries: { icon: "battery-full", label: () => "Batteries", toggleless: true, on: () => peri().length > 0,
                 face: () => { const l = peri(); if (!l.length) return { status: "No devices" };
                               const low = l.reduce((a, d) => d.percentage < a.percentage ? d : a);
                               return { status: batText(), hero: Math.round(low.percentage * 100) + "%", alert: low.percentage < 0.2 } },
                 status: () => batText(), act: () => {} },
    vpn:       { icon: "shield-check", label: () => "VPN", on: () => Tools.vpn !== "", act: () => Tools.vpnToggle(),
                 face: () => ({ status: Tools.vpn ? Tools.vpn.replace(/^ProtonVPN\s*/i, "") : "Off" }),
                 status: () => Tools.vpn ? Tools.vpn.replace(/^ProtonVPN\s*/i, "") : "Off" },
    timer:     { icon: "hourglass", label: () => Tools.timerMin > 0 ? "Timer" : "Stopwatch", on: () => Tools.tRun, act: () => Tools.tToggle(), details: () => Tools.tReset(),
                 status: () => Tools.tIdle ? (Tools.timerMin > 0 ? Tools.timerMin + " min" : "0:00") : Tools.mmss(Tools.tShown) + (Tools.tRun ? "" : " · paused"),
                 progress: () => Tools.timerMin > 0 && !Tools.tIdle ? Tools.tShown / Tools.tTotal : -1,
                 face: () => Tools.tIdle ? { status: Tools.timerMin > 0 ? Tools.timerMin + " min" : "Ready", hero: Tools.timerMin > 0 ? "" : "0:00" }
                                         : { status: Tools.tRun ? (Tools.timerMin > 0 ? "Running" : "Counting") : "Paused", hero: Tools.mmss(Tools.tShown) } },
  })
}
