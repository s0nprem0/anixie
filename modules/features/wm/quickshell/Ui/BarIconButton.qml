import QtQuick
import ".."

// A status readout with a glyph and a label beside it, such as a battery icon
// followed by its percentage. The glyph is fitted to its painted bounds inside
// a fixed canvas, and the pair is centred as a group so adding a label does not
// shift the icon off centre.
WidgetButton {
  id: root

  property real slotSize: Style.bar.iconSlot
  property real opticalSize: Style.bar.iconCanvas
  property real iconSize: Math.min(Style.bar.iconSize, opticalSize)
  property real opticalCenterErrorX: content.x + opticalCanvas.x
    + (glyph.paintedCenterX - root.width / 2)
    - (label.visible ? (label.implicitWidth + Style.space(4)) / 2 : 0)
  property real opticalCenterErrorY: content.y + glyph.paintedCenterY - root.height / 2
  property real glyphPaintedWidth: glyph.paintedWidth
  property real glyphPaintedHeight: glyph.paintedHeight

  property string labelText: ""
  property bool debugOpticalBounds: false

  readonly property real visualIconSize: Style.bar.iconSize
  readonly property real canvasSize: Math.max(visualIconSize, opticalSize)

  labelVisible: false
  hasVisualContent: text !== "" || labelText !== ""
  fontSize: Style.bar.iconFont
  fixedWidth: slotSize
  fixedHeight: -1

  Item {
    id: content
    // Exact coordinates rather than anchors, to preserve the centre of
    // odd-width slots.
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: root.canvasSize + (label.visible ? label.implicitWidth + Style.space(4) : 0)
    height: root.canvasSize

    Text {
      id: label
      visible: root.labelText !== ""
      textFormat: Text.PlainText
      text: root.labelText
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: root.active && root.useActiveColor ? root.activeColor : root.foreground
      y: (parent.height - height) / 2
        + (labelMetrics.descent - labelMetrics.ascent + labelMetrics.tightBoundingRect("0").height) / 2
      renderType: Text.NativeRendering
    }

    FontMetrics {
      id: labelMetrics
      font: label.font
    }

    Item {
      id: opticalCanvas
      x: label.visible ? label.implicitWidth + Style.space(4) : 0
      width: root.canvasSize
      height: root.canvasSize

      OpticalGlyph {
        id: glyph
        anchors.fill: parent
        text: root.text
        fontSize: Style.bar.iconFont
        paintedSize: root.visualIconSize
        color: root.active && root.useActiveColor ? root.activeColor : root.foreground
        rotation: root.textRotation
        debugBounds: root.debugOpticalBounds
      }
    }
  }
}