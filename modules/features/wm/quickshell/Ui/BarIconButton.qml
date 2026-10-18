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
    - (label.visible ? (label.width + Style.space(4)) / 2 : 0)
  property real opticalCenterErrorY: content.y + glyph.paintedCenterY - root.height / 2
  property real glyphPaintedWidth: glyph.paintedWidth
  property real glyphPaintedHeight: glyph.paintedHeight

  property string labelText: ""
  property bool debugOpticalBounds: false

  // How wide the label may run before it is elided. Without a cap a label is as
  // wide as its text, and the text is not always short: an MPRIS track title is
  // whatever the page happens to be playing, and a YouTube video called "Call of
  // Duty Modern Warfare 4 Campaign Gameplay Walkthrough Part 2 - CAPTAIN PRICE
  // (PS5 Pro)" is 700px of bar. It pushed the centre section out over the
  // workspaces on one side and the clock on the other. 0 means no cap, for a
  // caller that has its own.
  property int labelMaxWidth: 240

  readonly property real visualIconSize: Style.bar.iconSize
  readonly property real canvasSize: Math.max(visualIconSize, opticalSize)

  labelVisible: false
  hasVisualContent: text !== "" || labelText !== ""
  fontSize: Style.bar.iconFont

  // An icon on its own takes the fixed slot, so a row of them stays evenly
  // spaced. One carrying a label has to widen to whatever that label measures,
  // which is why the width is derived rather than guessed from a character
  // count.
  fixedWidth: -1
  fixedHeight: -1

  implicitWidth: labelText === ""
    ? slotSize
    : content.width + scaledHorizontalMargin * 2

  Item {
    id: content
    // Exact coordinates rather than anchors, to preserve the centre of
    // odd-width slots.
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: root.canvasSize + (label.visible ? label.width + Style.space(4) : 0)
    height: root.canvasSize

    Text {
      id: label
      visible: root.labelText !== ""
      textFormat: Text.PlainText
      text: root.labelText
      // Capped, then elided. `width` rather than `implicitWidth` so the cap reaches
      // the content box this sits in; the elide only happens because the width is
      // smaller than the text.
      width: root.labelMaxWidth > 0 ? Math.min(root.labelMaxWidth, implicitWidth) : implicitWidth
      elide: Text.ElideRight
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
      // `label.width`, not `label.implicitWidth`. They are the same until a label
      // is capped and elided, and then they are very different: the cap makes the
      // *width* 240 while the text still wants 700, so positioning the glyph off
      // the implicit width drew it 700px to the right of the label it belongs to
      // — out past the clock, with the widget's own box still only 260 wide.
      x: label.visible ? label.width + Style.space(4) : 0
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