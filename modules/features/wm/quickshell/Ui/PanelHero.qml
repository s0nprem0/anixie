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

  // An image to stand in for the glyph: the cover of what is playing, rather
  // than an icon for the fact that something is. Same slot, same job — it is
  // what the panel is about — and drawn larger, because a record sleeve in the
  // bar's sixteen pixels is a grey square.
  property string art: ""

  // Reserved width for a control on the right. Zero when the caller has none, so
  // the title takes the whole row.
  property int controlWidth: 0

  readonly property int glyphSlot: Style.bar.iconSlot
  readonly property bool hasGlyph: root.glyph !== ""
  readonly property bool hasArt: root.art !== ""
  readonly property int artSize: Style.space(48)
  readonly property int leadSlot: root.hasArt ? root.artSize : (root.hasGlyph ? root.glyphSlot : 0)

  implicitWidth: Math.max(titleText.implicitWidth, subtitleText.implicitWidth) + Style.space(12)
    + (root.leadSlot > 0 ? root.leadSlot + Style.space(10) : 0)
    + root.controlWidth
  implicitHeight: Math.max(titleText.implicitHeight + (root.hasSubtitle ? subtitleText.implicitHeight + Style.space(2) : 0), root.leadSlot)
  height: implicitHeight

  readonly property bool hasSubtitle: root.subtitle !== ""

  // Whichever of the two the caller asked for; both sit in the same slot on the
  // left, so a panel has one leading element rather than a glyph that moves when
  // the artwork arrives.
  OpticalGlyph {
    id: glyphLoader
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasGlyph && !root.hasArt
    width: root.hasGlyph && !root.hasArt ? Style.bar.iconCanvas : 0
    height: root.hasGlyph && !root.hasArt ? Style.bar.iconCanvas : 0
    text: root.glyph
    fontSize: Style.bar.iconFont
    paintedSize: Style.bar.iconSize
    color: Theme.primary
  }

  SizedImage {
    id: artImage
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasArt
    width: root.hasArt ? root.artSize : 0
    height: root.hasArt ? root.artSize : 0
    source: root.art
    fillMode: Image.PreserveAspectCrop
  }

  Text {
    id: titleText
    anchors.left: root.leadSlot > 0 ? leadItem.right : parent.left
    anchors.leftMargin: root.leadSlot > 0 ? Style.space(10) : 0
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

  // Whichever leading element is in play, as one anchorable edge: the title
  // hangs off the right of it whether that is a glyph or a sleeve.
  Item {
    id: leadItem
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: root.leadSlot
    height: root.leadSlot
    visible: width > 0
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