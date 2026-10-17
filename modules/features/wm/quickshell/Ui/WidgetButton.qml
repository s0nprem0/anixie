import QtQuick
import ".."

// The bar's button. One `pressed` signal carrying which button was used, so a
// module can map left, middle and right to three actions without three handlers,
// plus a wheel signal for scroll-to-adjust.
//
// A label that happens to be a private-use codepoint is drawn through
// OpticalGlyph instead of as text, so icons and words sit on the same optical
// size rather than being sized by their fonts.
Item {
  id: root

  property string text: ""
  property real fontSize: Style.font.body
  property color foreground: Theme.fg
  property color activeColor: Theme.accent

  property bool active: false
  property bool useActiveColor: true

  // A module that stands for a deliberate state — a chosen workspace, an
  // indicator that is on — keeps its block fill. Deliberately separate from
  // `active`, which only tints the glyph: a live microphone sets `active` as
  // its normal state and must not end up permanently highlighted.
  property bool selected: false

  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real textRotation: 0

  property bool keepSpace: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property bool pressable: true
  property bool labelVisible: true

  // Off for icon-font labels, whose figure metrics say nothing about the glyph.
  property bool centerFigures: true
  property bool hasVisualContent: text !== ""

  property string tooltipText: ""

  signal pressed(int button)
  signal wheelMoved(int delta)

  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
  readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
  readonly property bool labelShown: labelVisible && !iconLabel
  readonly property bool iconLabel: labelVisible && isIconGlyph(text)

  // Whether the pointer is genuinely resting on this button. The shared tooltip
  // asks for this rather than tracking enter and exit itself, because a button
  // can become un-hovered without either event firing: it may hide, dim or be
  // covered while the pointer has not moved at all.
  readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse

  function isIconGlyph(value) {
    const s = String(value || "")
    if (!s) return false

    const code = s.codePointAt(0)
    if (s.length !== (code > 0xffff ? 2 : 1)) return false

    return (code >= 0xe000 && code <= 0xf8ff)
      || (code >= 0xf0000 && code <= 0xffffd)
      || (code >= 0x100000 && code <= 0x10fffd)
      || (code >= 0x2190 && code <= 0x2bff)
  }

  visible: hasVisualContent || keepSpace
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)

  implicitWidth: fixedWidth > 0
    ? fixedWidth
    : (iconLabel ? Style.bar.iconSlot : Math.max(12, label.implicitWidth + scaledHorizontalMargin * 2))
  implicitHeight: fixedHeight > 0 ? fixedHeight : (iconLabel ? Style.bar.iconSlot : barSize)

  Behavior on opacity {
    NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
  }

  // The block: nothing at rest, a faint fill while the pointer is on it, and a
  // stronger one while the module is active. Deliberately no outline — an
  // outlined idle module reads as heavier than the reference's, which lets the
  // surface behind it do the separating.
  Rectangle {
    anchors.fill: parent
    radius: Theme.blockRadius

    color: {
      const alpha = root.selected
        ? Style.control.selectedFillAlpha
        : (mouseArea.containsMouse ? Style.control.hoverFillAlpha : 0)

      return alpha <= 0
        ? "transparent"
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, alpha)
    }

    Behavior on color {
      ColorAnimation { duration: Style.duration(120) }
    }
  }

  Text {
    id: label
    textFormat: Text.PlainText
    visible: root.labelShown
    anchors.centerIn: parent

    // Centring the line box leaves the figures sitting above the middle, since
    // the box keeps room for descenders. Centre the figure height instead, so
    // labels line up with the icons beside them.
    anchors.verticalCenterOffset: !root.centerFigures || root.text.indexOf("\n") !== -1
      ? 0
      : (labelMetrics.descent - labelMetrics.ascent + labelMetrics.tightBoundingRect("0").height) / 2

    text: root.text
    color: root.active && root.useActiveColor ? root.activeColor : root.foreground
    font.family: Style.font.family
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
      ColorAnimation { duration: Style.duration(160) }
    }
  }

  FontMetrics {
    id: labelMetrics
    font: label.font
  }

  Loader {
    id: iconLoader
    active: root.iconLabel
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    sourceComponent: Component {
      OpticalGlyph {
        text: root.text
        fontSize: Style.bar.iconFont
        paintedSize: Style.bar.iconSize
        color: root.active && root.useActiveColor ? root.activeColor : root.foreground
        rotation: root.textRotation
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor

    onEntered: TooltipHost.show(root.tooltipText, root)
    onExited: TooltipHost.hide(root)
    onClicked: function (mouse) {
      if (root.pressable) root.pressed(mouse.button)
    }
    onWheel: function (wheel) {
      root.wheelMoved(wheel.angleDelta.y)
    }
  }
}