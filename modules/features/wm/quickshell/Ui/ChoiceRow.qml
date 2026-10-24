import QtQuick
import ".."

// A row you pick from a list: a name, an optional line under it, and the state
// that says whether it is the one in use.
//
// Four panels list something you choose between — audio outputs, wireless
// networks, bluetooth devices, the player you are listening to — and each of
// them had drawn it differently: a dot with a click target the size of a
// pixel, a hover fill, a highlighted block, a bar button. They are one control
// and they live here once, so the lists cannot drift apart again.
//
// The whole row is the target, not a glyph in it. A 8px dot with the click area
// grown around it by ten pixels is a target you have to aim at; a row that
// fills the panel is one you press.
Item {
  id: root

  property string label: ""
  property string detail: ""

  // A glyph to the right of the name — the lock on a secured network, the state
  // of a device. Drawn as text, sized like the rest of the shell's glyphs.
  property string glyph: ""
  property color glyphColor: Theme.muted

  // Trailing content of the panel's own: signal bars, a percentage. Placed in a
  // slot of its own so the label can be elided against it rather than drawn
  // underneath it.
  default property alias trailing: trailingRow.data

  // Whether this is the entry currently in use. The shell's own rule for that:
  // the same soft fill over the foreground the bar uses for an active module, and
  // no outline. An accent-tinted block with a frame around it was the loudest
  // thing in the panel and the only outlined one anywhere in the shell, which
  // reads as a different control rather than as the chosen entry.
  property bool selected: false

  // Whether the row does anything. A list you cannot act on right now — the
  // radio is off — is dimmed rather than hidden: the entries are still what is
  // nearby, and the reason nothing happens is shown by the control that caused
  // it.
  property bool available: true

  signal clicked()

  // ---- the keyboard ----
  //
  // Being walked to by the panel's keys, and what a key does when it lands here.
  // A row is a choice, so Return is a click and the sideways keys mean nothing.
  readonly property bool panelFocusable: root.available

  function activate() {
    root.clicked()
  }

  function keyStep(direction) {
    return false
  }

  readonly property bool hasDetail: root.detail !== ""
  readonly property bool hasGlyph: root.glyph !== ""

  implicitWidth: trailingRow.implicitWidth + Style.space(12) + labelText.implicitWidth
  implicitHeight: Math.max(textColumn.height, trailingRow.implicitHeight, Style.space(24))
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    // Selected before hover, as elsewhere: pointing at the row you are already
    // on should not repaint it as though it were somewhere else.
    // The alphas are the point. 0.08 of the foreground is invisible on a dark
    // surface, and selected-versus-hovered was 0.18 against 0.22 — a step nobody
    // can see, animated or not. These are spaced far enough to read: a row under
    // the pointer is clearly lighter, and a selected row under it is lighter
    // again without losing its selection.
    color: mouse.pressed && root.available
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
      : (root.selected
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
            mouse.containsMouse && root.available
              ? Style.control.rowSelectedHoverAlpha
              : Style.control.selectedFillAlpha)
        : (mouse.containsMouse && root.available
          ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha)
          : "transparent"))

    // Short but eased, so the fill arrives rather than snaps. Reduce-motion
    // collapses it to zero like every other duration in the shell.
    Behavior on color {
      ColorAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic }
    }
  }

  Item {
    id: textColumn
    // Flush with the panel's own rows and section headers. The 8px inset made
    // every list sit a little to the right of the heading that named it.
    anchors.left: parent.left
    anchors.right: trailingRow.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    // Counted explicitly: `childrenRect` includes the detail line whether or not
    // it is shown, so a row without one was two pixels taller than its text and
    // pushed the label up out of the middle of its own row.
    height: labelText.height + (root.hasDetail ? Style.space(2) + detailText.height : 0)
    opacity: root.available ? 1 : Style.disabledOpacity

    Text {
      id: labelText
      width: parent.width - (root.hasGlyph ? glyphText.implicitWidth + Style.space(6) : 0)
      text: root.label
      // The accent is for the label of the entry in use, which is what accent
      // means everywhere else here — a bar module's active glyph, a switch that
      // is on. The fill says chosen; this says which one, without a frame.
      color: root.selected ? Theme.accent : Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: root.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideMiddle
      renderType: Text.NativeRendering
    }

    Text {
      id: glyphText
      anchors.right: parent.right
      anchors.verticalCenter: labelText.verticalCenter
      visible: root.hasGlyph
      text: root.glyph
      color: root.glyphColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: detailText
      anchors.top: labelText.bottom
      anchors.topMargin: root.hasDetail ? Style.space(2) : 0
      width: parent.width
      visible: root.hasDetail
      text: root.detail
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }
  }

  Row {
    id: trailingRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: implicitHeight
    opacity: root.available ? 1 : Style.disabledOpacity
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}