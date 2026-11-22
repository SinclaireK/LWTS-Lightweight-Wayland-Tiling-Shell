// What kind of app a name is (browser, terminal, game ...): desktop entries first (their Categories), then name rules (widgets/kinds.js).
// Kinds.ofProcess("helium") for a process / window class, Kinds.ofEntry(app) for a launcher result. Glyphs: widgets/UiKindIcon.qml.
pragma Singleton
import QtQuick
import Quickshell
import "../widgets/kinds.js" as K

Singleton {
  id: root
  readonly property var names: K.names
  function entryKind(a) { return K.fromCategories(a.categories) || K.fromName(a.id + " " + a.name) }
  function ofEntry(a) { return a ? entryKind(a) : "other" }
  // lowercase keys -> kind, rebuilt when the desktop entries (re)load; the cache is part of it, so it is dropped with it
  readonly property var index: {
    const m = ({}), apps = DesktopEntries.applications.values;
    for (const a of apps) {
      const k = entryKind(a);
      const keys = [String(a.id || "").replace(/\.desktop$/, ""), a.name, a.startupClass, a.command && a.command.length ? String(a.command[0]).split("/").pop() : ""];
      for (const s of keys) if (s) m[String(s).toLowerCase()] = k;
    }
    return { map: m, cache: ({}) }
  }
  function ofProcess(name) {
    const n = String(name || "").toLowerCase(), ix = index;
    if (ix.cache[n] !== undefined) return ix.cache[n];
    let k = ix.map[n];
    if (!k && n.length >= 15) { for (const key in ix.map) if (key.startsWith(n)) { k = ix.map[key]; break } }   // comm is cut at 15 characters
    const rule = K.fromName(n);
    if (!k || (k === "system" && rule !== "other" && rule !== "system")) k = rule;   // a desktop entry filed under "Utility" does not beat a clear name rule
    ix.cache[n] = k;
    return k
  }
}
