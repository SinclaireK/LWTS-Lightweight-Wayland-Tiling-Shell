import QtQuick
QtObject {
  property string section: "features"
  property var rows: [{ type: "tab", label: "Hello" }, { type: "header", label: "Test module" }, { type: "info", label: "Loaded from", value: "modules/hello" }]
}
