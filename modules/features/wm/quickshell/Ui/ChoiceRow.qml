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

  // Whether this is the entry currently in use. Filled and outlined, so it reads
  // as chosen at a glance from across the panel.
  property bool selected: false

  // Whether the row does anything. A list you cannot act on right now — the
  // radio is off — is dimmed rather than hidden: the entries are still what is
  // nearby, and the reason nothing happens is shown by the control that caused
  // it.
  property bool available: true

  signal clicked()

  readonly property bool hasDetail: root.detail !== ""
  readonly property bool hasGlyph: root.glyph !== ""

  implicitWidth: trailingRow.implicitWidth + Style.space(12) + labelText.implicitWidth
  implicitHeight: Math.max(textColumn.height, trailingRow.implicitHeight, Style.space(24))
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: root.selected
      ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.control.selectedFillAlpha)
      : (mouse.containsMouse && root.available
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
        : "transparent")
    border.color: root.selected ? Theme.accent : "transparent"
    border.width: 1

    Behavior on color { NumberAnimation { duration: Style.duration(120) } }
  }

  Item {
    id: textColumn
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.right: trailingRow.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: childrenRect.height
    opacity: root.available ? 1 : 0.45

    Text {
      id: labelText
      width: parent.width - (root.hasGlyph ? glyphText.implicitWidth + Style.space(6) : 0)
      text: root.label
      color: root.selected ? Theme.accent : Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideMiddle
      renderType: Text.NativeRendering
    }

    Text {
      id: glyphText
      anchors.right: parent.right
      anchors.top: parent.top
      visible: root.hasGlyph
      text: root.glyph
      color: root.glyphColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
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
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: implicitHeight
    opacity: root.available ? 1 : 0.45
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