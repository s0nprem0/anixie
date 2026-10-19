import QtQuick
import ".."

// The row at the top of a panel that names the thing the panel is *about* —
// "Wi-Fi", "Power", "Displays" — with its glyph and, optionally, one control on
// the right.
//
// Panels used to open with a plain title in the Panel card, which left the hero's
// own glyph slot to each panel that wanted one and gave the row no home for a
// control (a switch, a dropdown). This is that row: a glyph drawn on the optical
// size like everywhere else, a title and subtitle beside it, and a control slot
// on the right that reserves space whether or not a control is placed in it.
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property string glyph: ""

  // Reserved width for a control on the right. Zero when the caller has none, so
  // the title takes the whole row.
  property int controlWidth: 0

  readonly property int glyphSlot: Style.bar.iconSlot
  readonly property bool hasGlyph: root.glyph !== ""

  implicitWidth: Math.max(titleText.implicitWidth, subtitleText.implicitWidth) + Style.space(12)
    + (root.hasGlyph ? root.glyphSlot + Style.space(10) : 0)
    + root.controlWidth
  implicitHeight: Math.max(titleText.implicitHeight + (root.hasSubtitle ? subtitleText.implicitHeight + Style.space(2) : 0), root.hasGlyph ? root.glyphSlot : 0)
  height: implicitHeight

  readonly property bool hasSubtitle: root.subtitle !== ""

  OpticalGlyph {
    id: glyphLoader
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasGlyph
    width: root.hasGlyph ? Style.bar.iconCanvas : 0
    height: root.hasGlyph ? Style.bar.iconCanvas : 0
    text: root.glyph
    fontSize: Style.bar.iconFont
    paintedSize: Style.bar.iconSize
    color: Theme.primary
  }

  Text {
    id: titleText
    anchors.left: root.hasGlyph ? glyphLoader.right : parent.left
    anchors.leftMargin: root.hasGlyph ? Style.space(10) : 0
    anchors.top: parent.top
    anchors.right: controlSlot.left
    anchors.rightMargin: root.controlWidth > 0 ? Style.space(10) : 0
    text: root.title
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.DemiBold
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    width: Math.max(0, parent.width - x - (root.controlWidth > 0 ? controlSlot.width + Style.space(10) : 0))
  }

  Text {
    id: subtitleText
    anchors.left: titleText.left
    anchors.top: titleText.bottom
    anchors.topMargin: Style.space(2)
    text: root.subtitle
    visible: root.hasSubtitle
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    width: titleText.width
  }

  // Marks the slot a hero control anchors into, so the title can be placed to its
  // left. Invisible and empty; the control itself is declared by whoever uses the
  // hero.
  Item {
    id: controlSlot
    anchors.right: parent.right
    anchors.top: parent.top
    width: root.controlWidth
    height: root.height
    visible: false
  }
}