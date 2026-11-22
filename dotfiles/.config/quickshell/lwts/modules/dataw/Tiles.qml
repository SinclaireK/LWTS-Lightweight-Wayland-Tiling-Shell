// Launcher items of the data widgets (x_<id>) + the internet speed (built-in speed test, NetInfo).
import QtQuick
import qs.services
QtObject {
  function fmt(v) { return v ? [v.value, v.sub].filter(s => s).join(" · ") : "…" }
  property var defs: {
    const o = {};
    for (const d of DataW.defs) {
      const id = d.id;
      if (!d.cmd) {   // a shortcut: opens its link / runs its command
        o["x_" + id] = { icon: d.icon || DataW.iconFor(d.open || ""), label: () => d.label || id, toggleless: true, on: () => false, act: () => DataW.act(id),
                         status: () => d.open ? DataW.hostOf(d.open) : "Open", face: () => ({ status: d.open ? DataW.hostOf(d.open) : "Open" }) };
        continue;
      }
      o["x_" + id] = { icon: d.icon || "cube", label: () => d.label || id, status: () => fmt(DataW.values[id]),
                       on: () => !!(DataW.values[id] && DataW.values[id].on), act: () => DataW.act(id), toggleless: true,
                       face: () => { const v = DataW.values[id]; if (!v) return { status: "…" };
                                     const short = String(v.value || "").length <= 7 && /\d/.test(v.value || "");   // a short number is the hero, the sub is the line
                                     return short ? { status: v.sub || "", hero: v.value || "", alert: !!v.alert, icon: v.icon || "" } : { status: fmt(v), alert: !!v.alert, icon: v.icon || "" } } }
    }
    o.speed = { icon: "gauge", label: () => "Speed", toggleless: true, act: () => { if (!NetInfo.testing) NetInfo.speedTest() },
                face: () => NetInfo.testing ? { status: "Testing " + NetInfo.phase } : NetInfo.speed.failed ? { status: "Failed", alert: true }
                          : NetInfo.speed.down ? { status: "↑" + Math.round(NetInfo.speed.up) + " · " + Math.round(NetInfo.speed.ping) + " ms", hero: "↓" + Math.round(NetInfo.speed.down) }
                          : { status: "Enter = test" },
                on: () => NetInfo.testing,
                status: () => NetInfo.testing ? "Testing " + NetInfo.phase
                            : NetInfo.speed.failed ? "Failed" : NetInfo.speed.down ? "↓" + Math.round(NetInfo.speed.down) + " ↑" + Math.round(NetInfo.speed.up) + " Mb/s · " + Math.round(NetInfo.speed.ping) + " ms"
                            : "Enter = test" };
    return o;
  }
}
