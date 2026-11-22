// Progress ring: a faint full circle and an accent arc that drains clockwise from the top (p 1 -> 0). d = diameter.
import QtQuick
import QtQuick.Shapes
import qs.core

Shape {
  id: rg
  property real d: 26
  property real p: 0
  width: d; height: d
  preferredRendererType: Shape.CurveRenderer
  ShapePath { strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22); strokeWidth: 2; fillColor: "transparent"
    PathAngleArc { centerX: rg.d / 2; centerY: rg.d / 2; radiusX: rg.d / 2 - 1; radiusY: radiusX; startAngle: 0; sweepAngle: 360 } }
  ShapePath { strokeColor: Theme.accent; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
    PathAngleArc { centerX: rg.d / 2; centerY: rg.d / 2; radiusX: rg.d / 2 - 1; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * rg.p } }
}
