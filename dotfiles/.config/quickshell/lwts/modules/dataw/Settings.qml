// Settings -> Features -> Widgets: own data widgets (widgets.json) and shortcuts (a tile that opens a link or runs a command).
import QtQuick
import qs.core
import qs.services

QtObject {
  property string section: "preferences"
  function header(label) { return { type: "header", label } }
  function tab(label) { return { type: "tab", label } }
  function input(label, desc, get, set, o) { return Object.assign({ type: "input", label, desc, get, set }, o || {}) }
  property var rows: [
    tab("Modules"),
    header("New shortcut"),
    input("Name", "Empty = the site's name", () => DataW.newName, v => DataW.newName = v, { placeholder: "TikTok" }),
    input("Link or command", "https://… opens in its app; anything else runs as a command", () => DataW.newLink, v => DataW.newLink = v, { placeholder: "https://www.tiktok.com" }),
    { type: "action", label: "Add", desc: "It lands in Layout -> the bank (Own)", buttons: [["Add", () => DataW.addShortcut()]] },
    header("Own widgets and shortcuts"),
    ...DataW.defs.map(d => ({ type: "action", label: d.label || d.id, desc: d.cmd ? "Live data · " + Tiles.lookOf("x_" + d.id) : (d.open ? DataW.hostOf(d.open) : "Command") + " · " + Tiles.lookOf("x_" + d.id),
                              buttons: [["Remove", () => DataW.remove(d.id)]] })),
    { type: "action", label: "widgets.json", desc: "Edit by hand (commands that print a value)", buttons: [["Edit", () => DataW.edit()]] },
  ]
}
