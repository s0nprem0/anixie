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

  // Scroll the label through its slot instead of cutting it off. For a title
  // that is genuinely too long to elide usefully — a track name, where the end
  // of the string is as informative as the start — and not for anything that
  // wants to be read at a glance.
  property bool marquee: false

  // Held still while something it belongs to is open, so a popup does not sit
  // over text that is sliding around underneath it.
  property bool marqueePaused: false

  // Tuning for `marquee`: hold the opening of the string still long enough to
  // read a word of it, leave a little air before the next pass, and scroll at a
  // steady per-pixel rate so a longer title takes more time rather than moving
  // faster.
  property int marqueeDwell: 1600
  property int marqueeGap: 24
  property real marqueeSpeed: 22

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

  Component.onCompleted: restartMarquee()

  // The marquee restarts from the top whenever the label changes, so a new
  // track opens at its own beginning rather than wherever the last one was
  // caught mid-slide — "now playing" is the one label here whose text turns
  // over underneath the animation. It restarts on the other changes too — the
  // widget pausing, reduced motion, a title that now fits — so the label is
  // never left stranded off the edge.
  //
  // `running` is driven from here rather than bound: a bound `running` cannot be
  // restarted with `restart()` without that call breaking the binding, and the
  // sequence has to be re-entered from its first step for the reset to happen.
  function restartMarquee() {
    scrollAnim.stop()
    label.scrollX = 0
    if (label.scrolling && !marqueePaused) scrollAnim.restart()
  }

  Connections {
    target: label
    function onTextChanged() { root.restartMarquee() }
    function onScrollingChanged() { root.restartMarquee() }
  }

  Connections {
    target: root
    function onMarqueePausedChanged() { root.restartMarquee() }
  }

  Item {
    id: content
    // Exact coordinates rather than anchors, to preserve the centre of
    // odd-width slots.
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: root.canvasSize + (label.visible ? label.width + Style.space(4) : 0)
    height: root.canvasSize

    // The label's window: the label is exactly this wide, and in marquee mode it
    // is clipped to it and slides through. Without the clip the text would draw
    // straight over the glyph to its right.
    Item {
      id: labelBox
      x: 0
      width: label.width
      height: parent.height
      clip: root.marquee

      Text {
        id: label
        visible: root.labelText !== ""
        textFormat: Text.PlainText
        text: root.labelText
        // Capped, then elided. `width` rather than `implicitWidth` so the cap
        // reaches the content box this sits in; the elide only happens because
        // the width is smaller than the text.
        width: root.labelMaxWidth > 0 ? Math.min(root.labelMaxWidth, implicitWidth) : implicitWidth
        // A marquee shows the whole string by moving it, so there is nothing to
        // elide — an ellipsis on text that is about to scroll past is noise.
        // But when it is *not* moving — a title that fits, or reduce-motion —
        // the overflow has to be elided again, or a long title is simply cut.
        elide: label.scrolling ? Text.ElideNone : Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: root.active && root.useActiveColor ? root.activeColor : root.foreground
        y: (parent.height - height) / 2
          + (labelMetrics.descent - labelMetrics.ascent + labelMetrics.tightBoundingRect("0").height) / 2
        renderType: Text.NativeRendering

        // Only when it does not fit: a title that fits should sit still. Nor
        // under reduce-motion, where a label that moves is the very thing that
        // was turned off — the elide above comes back for the overflow.
        readonly property bool needsScroll: root.marquee && implicitWidth > labelBox.width
        readonly property bool scrolling: needsScroll && !Style.reduceMotion

        // The animated scroll offset, which `x` follows only while scrolling.
        // The old form animated `x` directly, and an explicit animation
        // permanently breaks a property's binding: once the label had scrolled,
        // a later track short enough to fit left it where the last frame ended,
        // which is off the edge — the title vanished instead of sitting still.
        property real scrollX: 0
        x: label.scrolling ? label.scrollX : 0
      }

      // Dwell, then slide out, and repeat. A bare `from: width; to: -text`
      // opens on a blank slot while the string travels in from off-screen, and
      // times the pass by text length, so a wide slot scrolled slower than a
      // narrow one. This names every step instead:
      //
      //   * the PropertyAction guarantees a readable opening frame — the start
      //     of the string, on screen, before anything moves;
      //   * the dwell holds it there long enough to read a word or two;
      //   * the slide is timed per pixel, so a long and a short title move at
      //     the same speed rather than the long one whipping past.
      //
      // Linear, because a marquee that eases reads as stopping rather than
      // passing. The loop restarts from the PropertyAction, and the snap back
      // to the start happens while the string is off the far edge, so the wrap
      // is never seen.
      SequentialAnimation {
        id: scrollAnim

        // Started by `restartMarquee`, not bound — see the comment there.
        loops: Animation.Infinite

        PropertyAction { target: label; property: "scrollX"; value: 0 }
        PauseAnimation { duration: root.marqueeDwell }

        NumberAnimation {
          target: label
          property: "scrollX"
          from: 0
          to: -(label.implicitWidth + root.marqueeGap)
          duration: Math.round((label.implicitWidth + root.marqueeGap) * root.marqueeSpeed)
          easing.type: Easing.Linear
        }
      }
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