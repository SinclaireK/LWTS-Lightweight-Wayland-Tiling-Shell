import QtQuick
import qs.services
QtObject {
  property var defs: ({
    night: { icon: "moon", label: () => "Night", on: () => Night.on, act: () => Night.toggle(), panel: "nightlight" }
  })
}
