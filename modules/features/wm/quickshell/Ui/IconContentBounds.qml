import QtQuick
import ".."

// Measures a glyph's painted (tight) bounds without scaling it, so callers can
// size or centre an icon to its actual ink rather than to its em box. A lighter
// alternative to OpticalGlyph when only the measurements are needed.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))

  readonly property bool hasBounds:
    metrics.tightBoundingRect.width > 0
    && metrics.tightBoundingRect.height > 0

  readonly property real tightWidth: hasBounds ? metrics.tightBoundingRect.width : 0
  readonly property real tightHeight: hasBounds ? metrics.tightBoundingRect.height : 0
  readonly property real tightX: hasBounds ? metrics.tightBoundingRect.x : 0
  readonly property real tightY: hasBounds ? metrics.tightBoundingRect.y : 0

  // Centre of the ink relative to the glyph's baseline origin.
  readonly property real centerX: hasBounds ? tightX + tightWidth / 2 : 0
  readonly property real centerY: hasBounds ? tightY + tightHeight / 2 : 0

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }
}
