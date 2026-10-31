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
  readonly property bool hasSubtitle: root.subtitle !== ""

  // Keep a long title or subtitle from forcing a panel wider than its content
  // needs to be. The text is elided inside the available space instead.
  readonly property real textContribution: Math.min(Style.space(220),
    Math.max(titleText.implicitWidth, subtitleText.implicitWidth))

  implicitWidth: root.leadSlot
    + (root.leadSlot > 0 ? Style.space(10) : 0)
    + root.textContribution
    + (root.controlWidth > 0 ? Style.space(10) + root.controlWidth : 0)
  implicitHeight: Math.max(root.textGroupHeight, root.leadSlot)
  height: implicitHeight

  readonly property int textGroupHeight: titleText.implicitHeight
    + (root.hasSubtitle ? Style.space(2) + subtitleText.implicitHeight : 0)

  // Whichever of the two the caller asked for; both sit in the same slot on the
  // left, so a panel has one leading element rather than a glyph that moves when
  // the artwork arrives.
  Item {
    id: leadItem
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: root.leadSlot
    height: root.leadSlot

    OpticalGlyph {
      anchors.centerIn: parent
      visible: root.hasGlyph && !root.hasArt
      width: root.hasGlyph && !root.hasArt ? Style.bar.iconCanvas : 0
      height: root.hasGlyph && !root.hasArt ? Style.bar.iconCanvas : 0
      text: root.glyph
      fontSize: Style.bar.iconFont
      paintedSize: Style.bar.iconSize
      color: Theme.primary
    }

    Rectangle {
      anchors.fill: parent
      visible: root.hasArt
      radius: Theme.cornerRadius
      color: "transparent"
      clip: true

      SizedImage {
        anchors.fill: parent
        source: root.art
        fillMode: Image.PreserveAspectFit
        smoothing: true
      }
    }
  }

  // The title and subtitle as one vertically centred group. The title keeps its
  // visual dominance; the subtitle sits a consistent step below it.
  Item {
    id: textGroup
    x: root.leadSlot > 0 ? leadItem.x + leadItem.width + Style.space(10) : 0
    width: Math.max(0, (root.controlWidth > 0 ? controlSlot.x - Style.space(10) : root.width) - x)
    y: Math.round((root.height - height) / 2)
    height: root.textGroupHeight

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      text: root.title
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      elide: Text.ElideRight
    }

    Text {
      id: subtitleText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.space(2)
      visible: root.hasSubtitle
      text: root.subtitle
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
      elide: Text.ElideRight
    }
  }

  // Marks the slot a hero control anchors into, so the title can be placed to
  // its left. Invisible and empty; the control itself is declared by whoever
  // uses the hero. It stays in the layout so callers can anchor to it.
  Item {
    id: controlSlot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.controlWidth
    height: root.height
    visible: false
  }
}
