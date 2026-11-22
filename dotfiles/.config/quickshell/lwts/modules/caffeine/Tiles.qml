import QtQuick
import qs.services
QtObject {
  property var defs: ({
    caffeine: { icon: "coffee", label: () => "Caffeine",
                status: () => Caffeine.on && Caffeine.until > 0 ? Math.max(0, Math.ceil((Caffeine.until - Date.now()) / 60000)) + " min left" : "",
                on: () => Caffeine.on, act: () => Caffeine.set(Caffeine.on ? -1 : 0),
                face: () => !Caffeine.on ? { status: "Off" } : Caffeine.until > 0 ? { status: "Min left", hero: String(Math.max(0, Math.ceil((Caffeine.until - Date.now()) / 60000))) } : { status: "Awake" } }
  })
}
