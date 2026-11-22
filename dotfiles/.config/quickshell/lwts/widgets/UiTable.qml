// Table (Tasks): sortable header + a scrolling list of rows (Nothing look: dotted rules, outline on the picked row, no filled plates).
// columns: [{ k (row field), label, kind (fn row -> app kind: a glyph before the text), w (px; 0 = takes the rest), right, meter (field 0..1 drawn as dots after the text), total (header note), color (fn row -> colour), fmt (fn row -> text), dot (fn row -> bool: LED) }]
// rows: [{...}] or a section row { hdr: "Apps", count: 4 }. Picked row = the one whose `rowKey` field equals `sel`.
import QtQuick
import qs.core

Item {
  id: t
  property var columns: []
  property var rows: []
  property var totals: ({})   // header notes by column key (live numbers: they must not live in `columns`, which has to stay a stable array)
  property string rowKey: "n"
  property string sel: ""
  property string sortBy: ""
  property real rowH: 32
  property bool showHeader: true
  signal sortRequested(string key)
  signal rowClicked(var row)
  readonly property real fixedW: columns.reduce((a, c) => a + (c.w || 0), 0)
  function colW(c) { return c.w > 0 ? c.w : Math.max(60, width - fixedW) }
  function pick(d) {   // move the pick by d rows (section rows are skipped)
    const items = rows.filter(r => !r.hdr);
    if (!items.length) return;
    let i = items.findIndex(r => String(r[rowKey]) === sel);
    i = i < 0 ? (d > 0 ? 0 : items.length - 1) : Math.max(0, Math.min(items.length - 1, i + d));
    sel = String(items[i][rowKey]); rowClicked(items[i]);
    list.positionViewAtIndex(rows.indexOf(items[i]), ListView.Contain)
  }

  Row {   // header
    id: head
    visible: t.showHeader
    height: visible ? 24 : 0
    Repeater {
      model: t.columns.length
      UiSortHead {
        required property int index
        readonly property var modelData: t.columns[index] || ({ k: "", label: "", w: 0 })
        width: t.colW(modelData); height: 24
        label: modelData.label; total: t.totals[modelData.k] || ""; alignRight: !!modelData.right
        active: t.sortBy === modelData.k
        enabled: t.sortBy !== "-"
        onClicked: t.sortRequested(modelData.k)
      }
    }
  }
  UiDotLine { id: rule; anchors.top: head.bottom; width: parent.width; visible: t.showHeader }

  ListView {
    id: list
    anchors { top: t.showHeader ? rule.bottom : parent.top; topMargin: t.showHeader ? 2 : 0; left: parent.left; right: parent.right; bottom: parent.bottom }
    clip: true; boundsBehavior: Flickable.StopAtBounds
    model: t.rows.length   // a count: the rows array is rebuilt every second, a new array as the model would reset the scroll and every delegate
    reuseItems: false
    delegate: Item {
      id: row
      required property int index
      readonly property var modelData: t.rows[index] || ({})
      readonly property bool hdr: !!modelData.hdr
      readonly property bool picked: !hdr && String(modelData[t.rowKey]) === t.sel
      width: list.width; height: t.rowH
      Rectangle { anchors.fill: parent; anchors.margins: 1; radius: Theme.radiusInner; color: "transparent"; visible: row.picked; border.width: 1; border.color: Theme.text }
      Rectangle { anchors.fill: parent; anchors.margins: 1; radius: Theme.radiusInner; color: Theme.fillHover; visible: !row.picked && !row.hdr && ma.containsMouse }
      MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !row.hdr; onClicked: { t.sel = String(row.modelData[t.rowKey]); t.rowClicked(row.modelData) } }
      Row {   // section header: APPS 4 ......
        visible: row.hdr
        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 8
        UiCaption { id: hl; text: row.hdr ? row.modelData.hdr : ""; color: Theme.text }
        UiCaption { id: hc; text: row.hdr ? String(row.modelData.count) : "" }
        UiDotLine { width: parent.width - hl.width - hc.width - 16; anchors.verticalCenter: parent.verticalCenter }
      }
      Row {
        visible: !row.hdr
        anchors.fill: parent
        Repeater {
          model: t.columns.length
          Item {
            id: cell
            required property int index
            readonly property var modelData: t.columns[index] || ({ k: "", w: 0 })
            width: t.colW(modelData); height: row.height
            readonly property string txt: row.hdr ? "" : (modelData.fmt ? modelData.fmt(row.modelData) : String(row.modelData[modelData.k] === undefined ? "" : row.modelData[modelData.k]))
            readonly property color tc: row.hdr || !modelData.color ? Theme.text : modelData.color(row.modelData)
            UiKindIcon { visible: !!modelData.kind && !row.hdr; kind: modelData.kind && !row.hdr ? modelData.kind(row.modelData) : "other"; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                         color: Theme.text; opacity: row.picked ? 1 : 0.7; faint: 0.14 }
            Rectangle { visible: !!modelData.dot && !row.hdr && modelData.dot(row.modelData); width: 6; height: 6; radius: 3; color: Theme.text; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
            Row {
              anchors { left: parent.left; leftMargin: modelData.kind ? 34 : modelData.dot ? 24 : 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
              spacing: 10
              layoutDirection: modelData.right ? Qt.RightToLeft : Qt.LeftToRight
              Text {
                width: Math.min(implicitWidth, parent.width - (modelData.meter ? 0 : 0)); elide: Text.ElideRight
                text: cell.txt; color: cell.tc
                font.family: modelData.mono ? Theme.label : Theme.font; font.capitalization: modelData.mono ? Font.AllUppercase : Font.MixedCase
                font.pixelSize: Math.round((modelData.mono ? 11 : 13) * Theme.scale)
              }
              DotMeter { visible: !!modelData.meter && !row.hdr; count: 20; dotSize: 3; gap: 2; anchors.verticalCenter: parent.verticalCenter
                         value: modelData.meter && !row.hdr ? Math.min(1, (row.modelData[modelData.meter] || 0)) : 0 }
            }
          }
        }
      }
    }
  }
}
