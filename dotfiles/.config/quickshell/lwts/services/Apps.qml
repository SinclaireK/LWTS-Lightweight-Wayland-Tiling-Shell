// Applications for the launcher search: .desktop entries ranked by pins and use count.
// Usage and pins: ~/.local/state/rice-launcher.json (the same file the old launcher used, history kept).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root
  property var usage: ({ counts: {}, pinned: [] })

  function score(name, q) {   // prefix, substring, then subsequence (fuzzy); -1 = no match
    name = (name || "").toLowerCase();
    if (name.startsWith(q)) return 0;
    if (name.includes(q)) return 1;
    let i = 0;
    for (const ch of name) if (ch === q[i]) i++;
    return i === q.length ? 2 : -1;
  }
  // Cyrillic queries: wrong layout ("вшысщкв" → discord) and transliteration ("дискорд" → discord).
  readonly property string ruKeys: "йцукенгшщзхъфывапролджэячсмитьбюёіїєґ"
  readonly property string enKeys: "qwertyuiop[]asdfghjkl;'zxcvbnm,.`s]'`"
  readonly property var translit: ({ а: "a", б: "b", в: "v", г: "g", ґ: "g", д: "d", е: "e", ё: "e", є: "e", ж: "zh", з: "z",
    и: "i", і: "i", ї: "i", й: "i", к: "k", л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f",
    х: "h", ц: "ts", ч: "ch", ш: "sh", щ: "sch", ъ: "", ы: "i", ь: "", э: "e", ю: "yu", я: "ya" })
  function swapLayout(q) { return Array.from(q, ch => { const i = ruKeys.indexOf(ch); return i < 0 ? ch : enKeys[i] }).join("") }
  function skeleton(s) {   // consonants only, c/q → k: "дискорд" and "discord" both → "dskrd"
    return s.replace(/ch/g, "h").replace(/ph/g, "f").replace(/[cq]/g, "k").replace(/x/g, "ks").replace(/w/g, "v")
            .replace(/[^a-z0-9]|[aeiouy]/g, "").replace(/(.)\1+/g, "$1");
  }
  function cyrScore(name, q) {
    let s = score(name, swapLayout(q));
    if (s >= 0) return s;
    const t = Array.from(q, ch => translit[ch] ?? ch).join("");
    s = score(name, t);
    if (s >= 0) return s + 0.5;
    const k = skeleton(t);
    return k.length >= 2 && skeleton((name || "").toLowerCase()).includes(k) ? 3 : -1;
  }
  function rank(a) { return (usage.pinned.includes(a.id) ? 1e6 : 0) + (usage.counts[a.id] || 0) }
  function search(q) {
    q = q.trim().toLowerCase();
    const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
    const cyr = /[а-яёіїєґ]/.test(q);
    return all.map(a => { const s = score(a.name, q); return { a, s: s < 0 && cyr ? cyrScore(a.name, q) : s } }).filter(x => x.s >= 0)
              .sort((x, y) => x.s - y.s || rank(y.a) - rank(x.a) || x.a.name.localeCompare(y.a.name))
              .map(x => x.a);
  }
  function pinned(a) { return usage.pinned.includes(a.id) }
  function launch(a) {
    const c = Object.assign({}, usage.counts); c[a.id] = (c[a.id] || 0) + 1;
    usage = { counts: c, pinned: usage.pinned }; save();
    a.execute();
  }
  function togglePin(a) {
    const p = pinned(a) ? usage.pinned.filter(x => x !== a.id) : usage.pinned.concat([a.id]);
    usage = { counts: usage.counts, pinned: p }; save();
  }
  function save() { file.setText(JSON.stringify(usage)) }

  FileView {
    id: file
    path: Quickshell.env("HOME") + "/.local/state/rice-launcher.json"
    onLoaded: { try { const d = JSON.parse(text()); root.usage = { counts: d.counts || {}, pinned: d.pinned || [] } } catch (e) {} }
  }
}
