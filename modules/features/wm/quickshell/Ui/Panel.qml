import QtQuick
import ".."

// The card a panel's contents sit in: a rounded surface with a title row, then
// whatever rows and controls the panel puts below it.
//
// Children a panel declares land in the content column rather than on the card
// itself, which is the whole point of the type.
//
// It is also where the keyboard lives. A panel is opened by a hotkey as often as
// by a click, and one that can only be pointed at sends you back to the mouse for
// the thing you opened it to do. The card is a focus scope that takes the keys
// (see PanelHost: the popup asks for the grab), walks the focusable controls in
// the order they are written, and reports what the focused one does when asked.
FocusScope {
  id: root

  // Children a panel declares land in the content column rather than on the
  // card itself, which is the whole point of the type.
  default property alias content: body.data

  property string title: ""

  // Whether the card holds the keys. True by default, and the one thing a panel
  // that is not the only window on screen would set false — a future panel drawn
  // beside this one, or a popup of its own, takes focus away by having it.
  focus: true

  // A `focus: true` scope alone does not hold the keyboard. The surface's own
  // exclusive focus routes the keys here, but an item still has to be the one
  // they land on, and a freshly mapped surface has none. The picker refocuses its
  // search field the same way, for the same reason.
  //
  // Only on creation: grabbing it back whenever it is lost would take it from a
  // dropdown's open list, which is the one thing in a panel that needs the
  // keyboard more than the panel itself.
  Component.onCompleted: Qt.callLater(function () { root.forceActiveFocus() })

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
  readonly property int maxHeight: Math.max(Style.space(200), PanelHost.panelMaxHeight)

  readonly property bool scrollable: body.implicitHeight > root.maxHeight

  implicitWidth: root.maxWidth
  implicitHeight: padding * 2
    + (header.visible ? header.implicitHeight + Style.space(10) : 0)
    + Math.min(body.implicitHeight, root.maxHeight)

  // Row width for panel contents. Exposed as a property because `body` is an id
  // local to this file and is not reachable from the panels that use it.
  readonly property real contentWidth: width - padding * 2

  readonly property int padding: Style.space(14)

  // ---- the keyboard ----
  //
  // Which control the keys are on, and whether the keys have been used at all.
  // Nothing is marked until one is: a ring that is already there when a panel is
  // opened by mouse reads as a selection the pointer never made, and the first
  // thing most people do with a panel is click in it.
  property Item focusedItem: null
  property bool keyboard: false

  // Where the ring is, in the scroller's coordinates, recomputed when the focus
  // moves and when the panel scrolls under it. Kept as numbers rather than bound
  // to `mapToItem`, whose result Qt cannot know to re-read when the content
  // moves.
  property real ringX: 0
  property real ringY: 0
  property real ringWidth: 0
  property real ringHeight: 0

  // Every control in the panel, in the order it is written.
  //
  // Walked every time the keys move rather than held: the lists inside a panel
  // are rebuilt as what they list changes — networks arrive and go, applications
  // start and stop — and a stop held from before the rebuild is an item that is
  // no longer on screen.
  function stops() {
    const found = []
    collect(body, found)
    return found
  }

  // A control is anything that says it is one. `panelFocusable` is the whole
  // interface for being walked to, and it is false for the rows that cannot be
  // used right now — a network row while the radio is off, a slider with no
  // device behind it — so the keys skip what the pointer cannot press either.
  //
  // Lists are walked into rather than treated as one stop: a list is where the
  // choosing happens, and a panel whose up and down do nothing inside it would
  // be a keyboard panel with the middle missing.
  function collect(item, found) {
    const children = item.children

    for (let i = 0; i < children.length; i++) {
      const child = children[i]
      if (!child || child.visible === false) continue

      if (child.panelFocusable === true) {
        // A row inside a hidden section is still "visible" as far as its own
        // property goes; what matters is whether it is drawn, all the way up.
        if (root.drawn(child)) found.push(child)
        continue
      }

      // A list holds its delegates in its content item, not in itself.
      if (child.contentItem && child.contentItem !== child) {
        collect(child.contentItem, found)
        continue
      }

      collect(child, found)
    }
  }

  // Whether the item is actually on screen: its own flag, and every ancestor's
  // between it and the card. A hidden section's rows would otherwise be walked to
  // and then drawn over by the row above them.
  function drawn(item) {
    let node = item
    while (node && node !== root) {
      if (node.visible === false) return false
      node = node.parent
    }
    return true
  }

  function moveCursor(delta) {
    const list = root.stops()
    if (list.length === 0) return

    let index = list.indexOf(root.focusedItem)
    // Nothing focused yet: either end of the list is the right way in.
    if (index < 0) index = delta > 0 ? -1 : 0

    // Wrapping, so that arrow-down from the last row is not a dead key.
    index = (index + delta + list.length) % list.length
    root.focusStop(list[index])
  }

  function focusStop(item) {
    root.focusedItem = item
    root.keyboard = true
    root.ensureVisible(item)
    root.updateRing()
  }

  // Bring the focused control into view before the ring is drawn around it — an
  // off-screen focus is a panel where the keys seem to have stopped working.
  function ensureVisible(item) {
    const top = item.mapToItem(body, 0, 0).y
    const bottom = top + item.height
    const margin = Style.space(8)

    if (top - margin < scroller.contentY) {
      scroller.contentY = Math.max(0, top - margin)
    } else if (bottom + margin > scroller.contentY + scroller.height) {
      scroller.contentY = Math.min(
        Math.max(0, scroller.contentHeight - scroller.height),
        bottom + margin - scroller.height)
    }
  }

  function updateRing() {
    const item = root.focusedItem
    if (!item) {
      root.ringWidth = 0
      root.ringHeight = 0
      return
    }

    // Mapped into the scroller, whose coordinate space is the viewport: the
    // content item is positioned at the scroll offset, so this already accounts
    // for it.
    const origin = item.mapToItem(scroller, 0, 0)
    root.ringX = origin.x - Style.space(2)
    root.ringY = origin.y - Style.space(2)
    root.ringWidth = item.width + Style.space(4)
    root.ringHeight = item.height + Style.space(4)
  }

  function activateFocused() {
    if (root.focusedItem) root.focusedItem.activate()
  }

  function stepFocused(direction) {
    if (root.focusedItem) return root.focusedItem.keyStep(direction)
    return false
  }

  Keys.onPressed: function (event) {
    switch (event.key) {
    case Qt.Key_Down:
      root.moveCursor(1)
      event.accepted = true
      break
    case Qt.Key_Up:
      root.moveCursor(-1)
      event.accepted = true
      break
    // Tab is the panel's neighbour, not the next control: with several panels
    // open — which is the point of the host holding a list — the keyboard has to
    // be able to cross between them. The arrows are what walk this panel's own
    // controls, which is how Omarchy's panels divide the same two jobs.
    case Qt.Key_Tab:
      PanelHost.focusNext(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
      break
    case Qt.Key_Backtab:
      PanelHost.focusNext(-1)
      event.accepted = true
      break
    case Qt.Key_Home:
      root.moveCursor(root.stops().length)
      event.accepted = true
      break
    case Qt.Key_End:
      root.moveCursor(-1)
      event.accepted = true
      break
    case Qt.Key_Return:
    case Qt.Key_Enter:
    case Qt.Key_Space:
      root.activateFocused()
      event.accepted = true
      break
    // The focused control says whether the sideways keys mean anything to it: a
    // slider takes them as a level, a list of chips as a choice, a row of text
    // as nothing at all.
    case Qt.Key_Right:
      event.accepted = root.stepFocused(1)
      break
    case Qt.Key_Left:
      event.accepted = root.stepFocused(-1)
      break
    case Qt.Key_Escape:
      // The panel the keys are on, not all of them: with several open, one
      // Escape putting them all away would make the rest unreachable by keyboard.
      PanelHost.closeFocused()
      event.accepted = true
      break
    }
  }

  // Reaching for the pointer means the ring is no longer what is being followed.
  // Also exposed for panels that own their hover behaviour, such as the tray
  // drawer, so they do not have to add a second handler and guess what it covers.
  readonly property bool pointerInside: panelHover.hovered

  HoverHandler {
    id: panelHover
    onHoveredChanged: if (hovered) root.keyboard = false
  }

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

    // The ring is placed against this, so it has to follow when the content
    // moves under it.
    onContentYChanged: root.updateRing()

    ScrollBar.vertical: ScrollBar {}

    Column {
      id: body
      width: scroller.width
      spacing: Style.space(8)
    }
  }

  // The ring, drawn over the scroller and clipped to it so it cannot escape the
  // card, inset by a couple of pixels so it sits around the control rather than
  // on its edge.
  Item {
    anchors.fill: scroller
    clip: true
    visible: root.keyboard && root.ringWidth > 0

    Rectangle {
      x: root.ringX
      y: root.ringY
      width: root.ringWidth
      height: root.ringHeight
      radius: Theme.cornerRadius
      color: "transparent"
      border.color: Theme.primary
      border.width: 1
    }
  }
}