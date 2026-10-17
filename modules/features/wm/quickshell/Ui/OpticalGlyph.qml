import QtQuick
import ".."

// Measures a glyph's painted bounds and scales it to `paintedSize`, preserving
// its aspect ratio. A font's point size says nothing about how much ink a
// glyph actually lays down, so bar icons are fitted to what they paint rather
// than to their em box — that is what keeps a row of unrelated icons optically
// equal. Reports the painted centre too, so callers can correct for glyphs
// whose ink sits off-centre in its own cell.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real paintedSize: 0
  property color color: Theme.fg
  property real rotation: 0
  property bool debugBounds: false

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
  readonly property real tightHeight: Math.max(1, glyphMetrics.tightBoundingRect.height)
  readonly property real paintedScale: paintedSize > 0
    ? Math.min(paintedSize, width, height) / Math.max(tightWidth, tightHeight)
    : 1
  readonly property real paintedWidth: tightWidth * paintedScale
  readonly property real paintedHeight: tightHeight * paintedScale
  readonly property real paintedCenterX: glyph.x + (glyphMetrics.tightBoundingRect.x + tightWidth / 2) * paintedScale
  readonly property real paintedCenterY: glyph.y + (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y + tightHeight / 2) * paintedScale

  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }

  Text {
    id: glyph
    textFormat: Text.PlainText
    x: root.width / 2 - (glyphMetrics.tightBoundingRect.x + root.tightWidth / 2) * root.paintedScale
    y: root.paintedSize > 0
      ? root.height / 2 - (baselineOffset + glyphMetrics.tightBoundingRect.y + root.tightHeight / 2) * root.paintedScale
      : Math.round((root.height - height) / 2)
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    transformOrigin: Item.TopLeft
    scale: root.paintedScale
    rotation: root.rotation
    renderType: root.paintedSize > 0 ? Text.CurveRendering : Text.NativeRendering
  }

  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }
}