pragma ComponentBehavior: Bound
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

  // A glyph with no ink (empty or whitespace-only text) reports no painted
  // bounds, so callers can distinguish it from a real glyph that happens to be
  // small. The raw tight rect is never padded to a single pixel.
  readonly property bool hasPaintedBounds:
    glyphMetrics.tightBoundingRect.width > 0
    && glyphMetrics.tightBoundingRect.height > 0

  readonly property real tightWidth: hasPaintedBounds
    ? glyphMetrics.tightBoundingRect.width
    : 0
  readonly property real tightHeight: hasPaintedBounds
    ? glyphMetrics.tightBoundingRect.height
    : 0

  // Safe denominator handling: a missing glyph or unusable component size never
  // produces NaN or a negative scale.
  readonly property real paintedScale: {
    if (paintedSize <= 0 || !hasPaintedBounds) return 1

    const longest = Math.max(tightWidth, tightHeight)
    if (!Number.isFinite(longest) || longest <= 0) return 1

    const available = Math.min(paintedSize, Math.max(0, width), Math.max(0, height))
    if (!Number.isFinite(available) || available <= 0) return 0

    return available / longest
  }

  readonly property real paintedWidth: tightWidth * paintedScale
  readonly property real paintedHeight: tightHeight * paintedScale

  // Unrotated painted centre, in this component's local coordinates.
  readonly property real unrotatedCenterX: hasPaintedBounds
    ? glyph.x + (glyphMetrics.tightBoundingRect.x + tightWidth / 2) * paintedScale
    : 0
  readonly property real unrotatedCenterY: hasPaintedBounds
    ? glyph.y + (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y + tightHeight / 2) * paintedScale
    : 0

  // The Text item is scaled and rotated about its own top-left corner, so the
  // reported centre is rotated by the same transform rather than approximated.
  readonly property real paintedCenterX: hasPaintedBounds
    ? glyph.x + (unrotatedCenterX - glyph.x) * Math.cos(rotation * Math.PI / 180)
      - (unrotatedCenterY - glyph.y) * Math.sin(rotation * Math.PI / 180)
    : 0
  readonly property real paintedCenterY: hasPaintedBounds
    ? glyph.y + (unrotatedCenterX - glyph.x) * Math.sin(rotation * Math.PI / 180)
      + (unrotatedCenterY - glyph.y) * Math.cos(rotation * Math.PI / 180)
    : 0

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

  // Component bounds, for reference.
  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }

  // Untransformed tight bounds.
  Rectangle {
    visible: root.debugBounds && root.hasPaintedBounds
    x: glyph.x + glyphMetrics.tightBoundingRect.x * root.paintedScale
    y: glyph.y + (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y) * root.paintedScale
    width: root.paintedWidth
    height: root.paintedHeight
    color: "transparent"
    border.width: 1
    border.color: "#44ff88"
  }

  // Final transformed painted bounds, when rotation is in use.
  Rectangle {
    visible: root.debugBounds && root.hasPaintedBounds && root.rotation !== 0
    x: glyph.x + glyphMetrics.tightBoundingRect.x * root.paintedScale
    y: glyph.y + (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y) * root.paintedScale
    width: root.paintedWidth
    height: root.paintedHeight
    color: "transparent"
    border.width: 1
    border.color: "#ff8844"
    transformOrigin: Item.TopLeft
    rotation: root.rotation
  }
}