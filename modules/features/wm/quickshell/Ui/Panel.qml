import QtQuick
import ".."

// The card a panel's contents sit in: a rounded surface with a title row, then
// whatever rows and controls the panel puts below it.
//
// Children a panel declares land in the content column rather than on the card
// itself, which is the whole point of the type.
Item {
  id: root

  // Children a panel declares land in the content column rather than on the
  // card itself, which is the whole point of the type.
  default property alias content: body.data

  property string title: ""

  // The panel's width, stated rather than measured.
  //
  // It used to be `min(maxWidth, content + padding)`, which is circular: the
  // rows inside a panel set their width from `contentWidth`, which comes from
  // this card's width, which was coming from the content. Qt resolved the loop
  // to nothing and the panels that use this card as their root — the brightness
  // one, Bluetooth, the media popup — came up collapsed, with their labels
  // drawn on top of their own controls. A panel is a fixed-width card; the
  // content is laid out inside it, not the other way round.
  property int maxWidth: Style.space(340)

  // How tall the card may get before its contents start to scroll.
  //
  // A panel's height is its content's height, and a panel's content is however
  // much of it there is: twenty entries of notification history, a dozen audio
  // applications. Left unclamped the window simply runs off the bottom of the
  // screen, and the rows past the edge cannot be read or reached. The screen's
  // own height is the ceiling, less the bar and a margin, so the cap follows
  // the machine rather than a number guessed for one of them.
  readonly property int maxHeight: Math.max(Style.space(200),
    (PanelHost.shown ? PanelHost.screenHeight : 1080) - Style.bar.sizeHorizontal - Style.space(24))

  readonly property bool scrollable: body.implicitHeight > root.maxHeight

  implicitWidth: root.maxWidth
  implicitHeight: padding * 2
    + (header.visible ? header.implicitHeight + Style.space(10) : 0)
    + Math.min(body.implicitHeight, root.maxHeight)

  // Row width for panel contents. Exposed as a property because `body` is an id
  // local to this file and is not reachable from the panels that use it.
  readonly property real contentWidth: width - padding * 2

  readonly property int padding: Style.space(14)

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.muted
    border.width: 1
  }

  Text {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.padding
    anchors.leftMargin: root.padding
    anchors.rightMargin: root.padding
    visible: root.title !== ""
    text: root.title
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.DemiBold
  }

  // The scrolling. A panel that fits is not clipped and cannot be dragged; one
  // that does not scrolls, with the shell's own scrollbar rather than a stock
  // one that would draw a trough across the card.
  //
  // The wheel is left on deliberately. Every panel is read by scrolling or by
  // dragging, and a panel full of rows that silently swallowed the wheel reads
  // as broken on the first try.
  Flickable {
    id: scroller
    anchors.top: header.visible ? header.bottom : parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.topMargin: header.visible ? Style.space(10) : root.padding
    anchors.leftMargin: root.padding
    // The scrollbar sits inside the flickable's right edge, so the gap it takes
    // is taken off the content rather than off the card: a panel that scrolls
    // must not lay its text under its own scrollbar, and must not jump sideways
    // when it starts to.
    anchors.rightMargin: root.padding + (root.scrollable ? Style.space(8) : 0)
    anchors.bottomMargin: root.padding

    contentWidth: width
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    // Nothing to drag when everything fits, so the panel does not steal the
    // pointer from the controls inside it for a gesture that would do nothing.
    interactive: root.scrollable

    ScrollBar.vertical: ScrollBar {}

    Column {
      id: body
      width: scroller.width
      spacing: Style.space(8)
    }
  }
}