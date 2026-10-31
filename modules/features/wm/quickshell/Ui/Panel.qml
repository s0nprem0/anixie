import QtQuick
import ".."

// The card a panel's contents sit in: a surface, a scroller, and the keyboard.
//
// The heading is the panel's own PanelHero, not a second title owned here. Two
// header treatments meant the System and Clock panels looked like a different
// kind of card from every other one; this type is now only the container.
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

  // Whether the card holds the keys. True by default, and the one thing a panel
  // that is not the only window on screen would set false — a future panel drawn
  // beside this one, or a popup of its own, takes focus away by having it.
  focus: true

  // Whether PanelHost owns this card. The tray drawer is the exception: it keeps
  // its window — and the parked widgets that anchor their own panels from inside
  // it — alive while closed, so it is not one of the host's open panels and has
  // to close itself on Escape and keep Tab inside itself.
  property bool hosted: true
  property var closeHandler: null

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
  readonly property int maxHeight: Math.max(Style.space(200),
    PanelHost.maxHeightFor(root.Screen ? root.Screen.height : 1080))

  readonly property bool scrollable: body.implicitHeight > root.maxHeight

  implicitWidth: root.maxWidth
  implicitHeight: padding * 2 + Math.min(body.implicitHeight, root.maxHeight)

  // Row width for panel contents. Exposed as a property because `body` is an id
  // local to this file and is not reachable from the panels that use it.
  readonly property real contentWidth: width - padding * 2

  readonly property int padding: Style.space(14)

  // Whether Tab/Shift+Tab wrap around the control list. Kept configurable so a
  // future panel can opt out without changing the rest of the navigation model.
  property bool wrapNavigation: true

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

  // ---- helpers ----

  function isAlive(item) {
    if (!item) return false
    try {
      const value = item.visible
      return true
    } catch (e) {
      return false
    }
  }

  function isAvailable(item) {
    if (!isAlive(item)) return false
    try {
      if (item.visible === false) return false
      if (item.enabled === false) return false
      if (item.panelFocusable !== true) return false
    } catch (e) {
      return false
    }
    return true
  }

  function isDescendant(item, ancestor) {
    let node = item
    while (node) {
      if (node === ancestor) return true
      try {
        node = node.parent
      } catch (e) {
        return false
      }
    }
    return false
  }

  function windowActiveFocusItem() {
    try {
      const win = root.Window && root.Window.window ? root.Window.window : null
      return win ? win.activeFocusItem : null
    } catch (e) {
      return null
    }
  }

  function isTextInput(item) {
    if (!isAlive(item)) return false
    try {
      return typeof item.cursorPosition !== "undefined"
        && typeof item.text !== "undefined"
        && typeof item.select === "function"
    } catch (e) {
      return false
    }
  }

  function activeFocusIsTextInput() {
    return isTextInput(root.windowActiveFocusItem())
  }

  // Every control in the panel, in the order it is written.
  //
  // Cached to avoid rebuilding the whole tree on every key repeat/move; rebuilt
  // when the structure changes or focus state shifts.
  property var _stopsCache: []
  property bool _stopsDirty: true

  function invalidateStops() {
    root._stopsDirty = true
  }

  function rebuildStops() {
    const found = []
    try {
      root.collect(body, found)
    } catch (e) {
    }

    const out = []
    for (let i = 0; i < found.length; i++) {
      const item = found[i]
      if (!root.isAvailable(item)) continue
      if (out.indexOf(item) < 0) out.push(item)
    }
    root._stopsCache = out
    root._stopsDirty = false
    return out
  }

  function stops() {
    if (root._stopsDirty) return root.rebuildStops()
    return root._stopsCache
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
    if (!item) return
    let children = []
    try {
      children = item.children || []
    } catch (e) {
      children = []
    }

    for (let i = 0; i < children.length; i++) {
      const child = children[i]
      if (!child || !root.isAlive(child)) continue

      let visible = true
      try {
        visible = child.visible !== false
      } catch (e) {
        visible = false
      }
      if (!visible) continue

      let panelFocusable = false
      try {
        panelFocusable = child.panelFocusable === true
      } catch (e) {
        panelFocusable = false
      }

      if (panelFocusable) {
        // A focusable control owns its own descendants: the row is one stop
        // even when it contains a switch or a stepper inside it.
        if (root.drawn(child) && found.indexOf(child) < 0) found.push(child)
        continue
      }

      // A list holds its delegates in its content item, not in itself.
      let contentItem = null
      try {
        contentItem = child.contentItem
      } catch (e) {
        contentItem = null
      }
      if (contentItem && contentItem !== child) {
        root.collect(contentItem, found)
        continue
      }

      root.collect(child, found)
    }
  }

  // Whether the item is actually on screen: its own flag, and every ancestor's
  // between it and the card. A hidden section's rows would otherwise be walked to
  // and then drawn over by the row above them.
  function drawn(item) {
    let node = item
    while (node && node !== root) {
      try {
        if (node.visible === false) return false
      } catch (e) {
        return false
      }
      try {
        node = node.parent
      } catch (e) {
        return false
      }
    }
    return node === root
  }

  function moveCursor(delta) {
    const list = root.stops()
    if (list.length === 0) return

    let index = list.indexOf(root.focusedItem)
    if (index < 0) index = delta > 0 ? -1 : 0

    if (root.wrapNavigation) {
      index = (index + delta + list.length) % list.length
    } else {
      index = Math.max(0, Math.min(list.length - 1, index + delta))
    }

    if (list.length > 0) root.focusStop(list[index])
  }

  function firstStop() {
    const list = root.stops()
    if (list.length > 0) root.focusStop(list[0])
  }

  function lastStop() {
    const list = root.stops()
    if (list.length > 0) root.focusStop(list[list.length - 1])
  }

  function focusStop(item) {
    if (!root.isAvailable(item)) return
    root.focusedItem = item
    root.keyboard = true
    try {
      item.forceActiveFocus()
    } catch (e) {
    }
    root.ensureVisible(item)
    root.updateRing()
  }

  // Bring the focused control into view before the ring is drawn around it — an
  // off-screen focus is a panel where the keys seem to have stopped working.
  function ensureVisible(item) {
    if (!item || !root.isAlive(item)) return
    let top = 0
    let itemHeight = 0
    try {
      const origin = item.mapToItem(body, 0, 0)
      top = origin.y
      itemHeight = item.height
    } catch (e) {
      return
    }

    const bottom = top + itemHeight
    const margin = Style.space(8)
    const maxContentY = Math.max(0, scroller.contentHeight - scroller.height)

    if (itemHeight >= scroller.height) {
      if (top < scroller.contentY || bottom > scroller.contentY + scroller.height) {
        scroller.contentY = Math.max(0, Math.min(maxContentY, top - margin))
      }
    } else {
      if (top - margin < scroller.contentY) {
        scroller.contentY = Math.max(0, top - margin)
      } else if (bottom + margin > scroller.contentY + scroller.height) {
        scroller.contentY = Math.min(maxContentY, bottom + margin - scroller.height)
      }
    }
  }

  function updateRing() {
    const item = root.focusedItem
    if (!item || !root.isAvailable(item)) {
      root.ringWidth = 0
      root.ringHeight = 0
      return
    }
    try {
      const origin = item.mapToItem(scroller, 0, 0)
      root.ringX = origin.x - Style.space(2)
      root.ringY = origin.y - Style.space(2)
      root.ringWidth = item.width + Style.space(4)
      root.ringHeight = item.height + Style.space(4)
    } catch (e) {
      root.ringWidth = 0
      root.ringHeight = 0
    }
  }

  function activateFocused() {
    const item = root.focusedItem
    if (!item || !root.isAvailable(item)) {
      root.focusedItem = null
      return
    }
    if (typeof item.activate === "function") {
      try {
        item.activate()
      } catch (e) {
      }
    }
  }

  function stepFocused(direction) {
    const item = root.focusedItem
    if (!item || !root.isAvailable(item)) {
      root.focusedItem = null
      return false
    }
    if (typeof item.keyStep === "function") {
      try {
        return !!item.keyStep(direction)
      } catch (e) {
        return false
      }
    }
    return false
  }

  // Keep the custom cursor honest about Qt's own focus. A clicked control or a
  // restored focus from a popup should become the panel's focused control, and
  // a destroyed or hidden one should be dropped instead of lingering.
  onActiveFocusChanged: {
    if (!root.activeFocus) return
    root.invalidateStops()
    Qt.callLater(function () {
      if (!root.activeFocus) return
      const active = root.windowActiveFocusItem()
      if (active && active !== root && root.isDescendant(active, root)) {
        const list = root.stops()
        const index = list.indexOf(active)
        if (index >= 0) {
          root.focusedItem = active
        } else {
          let node = active
          let found = null
          while (node && node !== root) {
            if (list.indexOf(node) >= 0) {
              found = node
              break
            }
            try {
              node = node.parent
            } catch (e) {
              node = null
            }
          }
          if (found) root.focusedItem = found
        }
      } else if (root.focusedItem && root.isAvailable(root.focusedItem)) {
        try {
          root.focusedItem.forceActiveFocus()
        } catch (e) {
        }
      }
      root.updateRing()
    })
  }

  onFocusedItemChanged: {
    root.updateRing()
  }

  onWidthChanged: root.updateRing()
  onHeightChanged: root.updateRing()

  // Clear the cursor when the control it points at disappears, is disabled, or
  // is destroyed, so navigation recovers instead of holding a dead reference.
  Connections {
    target: root.focusedItem
    enabled: root.focusedItem !== null
    function onVisibleChanged() {
      const item = root.focusedItem
      if (item && item.visible === false) root.focusedItem = null
    }
    function onEnabledChanged() {
      const item = root.focusedItem
      if (item && item.enabled === false) root.focusedItem = null
    }
    function onPanelFocusableChanged() {
      const item = root.focusedItem
      if (item && item.panelFocusable !== true) root.focusedItem = null
    }
    function onParentChanged() {
      const item = root.focusedItem
      if (!item || item.parent === null) root.focusedItem = null
    }
    function onXChanged() { root.updateRing() }
    function onYChanged() { root.updateRing() }
    function onWidthChanged() { root.updateRing() }
    function onHeightChanged() { root.updateRing() }
  }

  Connections {
    target: scroller
    function onContentYChanged() { root.updateRing() }
    function onWidthChanged() { root.updateRing() }
    function onHeightChanged() { root.updateRing() }
  }

  Keys.onPressed: function (event) {
    // Text fields own their editing keys; do not walk the panel while one is
    // being edited.
    if (root.activeFocusIsTextInput()) {
      if (event.key === Qt.Key_Escape) {
        if (root.closeHandler) root.closeHandler()
        else PanelHost.closeFocused()
        event.accepted = true
      }
      return
    }

    const autoRepeat = !!event.isAutoRepeat

    switch (event.key) {
    case Qt.Key_Down:
      root.moveCursor(1)
      event.accepted = true
      break
    case Qt.Key_Up:
      root.moveCursor(-1)
      event.accepted = true
      break
    // Tab crosses to a panel on another screen when there is one; on a single
    // screen it walks this panel's own controls, the way Tab does everywhere
    // else. The arrows do the same walk, so a panel never needs Tab to be usable.
    case Qt.Key_Tab:
      if (!root.hosted || PanelHost.openPanels.count < 2) root.moveCursor(1)
      else PanelHost.focusNext(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
      break
    case Qt.Key_Backtab:
      if (!root.hosted || PanelHost.openPanels.count < 2) root.moveCursor(-1)
      else PanelHost.focusNext(-1)
      event.accepted = true
      break
    case Qt.Key_Home:
      root.firstStop()
      event.accepted = true
      break
    case Qt.Key_End:
      root.lastStop()
      event.accepted = true
      break
    case Qt.Key_Return:
    case Qt.Key_Enter:
    case Qt.Key_Space:
      if (autoRepeat) {
        event.accepted = true
        break
      }
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
      if (root.closeHandler) root.closeHandler()
      else PanelHost.closeFocused()
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
    border.color: Theme.border
    border.width: Style.strokeWidth
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
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.topMargin: root.padding
    anchors.leftMargin: root.padding
    // Keep the scrollbar gutter reserved in both states so the content width
    // does not change the moment scrolling becomes necessary.
    anchors.rightMargin: root.padding + Style.space(8)
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
      onChildrenChanged: root.invalidateStops()
      onVisibleChanged: root.invalidateStops()
    }
  }

  // The ring, drawn over the scroller and clipped to it so it cannot escape the
  // card, inset by a couple of pixels so it sits around the control rather than
  // on its edge.
  Item {
    anchors.fill: scroller
    clip: true
    opacity: (root.keyboard && !root.pointerInside && root.ringWidth > 0
              && root.isAvailable(root.focusedItem)) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
    }

    Rectangle {
      x: root.ringX
      y: root.ringY
      width: root.ringWidth
      height: root.ringHeight
      radius: Theme.cornerRadius
      color: "transparent"
      border.color: Theme.primary
      border.width: Style.strokeWidth
    }
  }
}
