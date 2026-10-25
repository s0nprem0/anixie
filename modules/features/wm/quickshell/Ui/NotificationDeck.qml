import QtQuick
import ".."
import "."

// A source's notifications, as a small deck: the newest card is the front, and
// the rest peek out underneath. Hovering opens the deck into its individual
// cards so every message can be read and acted on without going to history.
//
// The deck itself only decides what is drawn. Each card still owns its expiry,
// actions and clicks, so opening a deck does not put a second set of controls on
// screen.
Item {
  id: root

  property var items: []
  property bool replay: false
  property bool forceExpanded: false

  // The history panel shows the same live cards. While it is open the hidden
  // toasts must stop their expiry clocks, or a card the user is reading in the
  // panel would be dismissed from behind them.
  property bool paused: false

  readonly property int count: root.items.length
  readonly property int peekCount: Math.min(2, Math.max(0, root.count - 1))
  readonly property bool expanded: root.forceExpanded || root.items.length <= 1 || hover.hovered

  // One number, one animation: the peeks recede and the full column fades in
  // from the same clock rather than each item inventing its own duration.
  property real progress: root.expanded ? 1 : 0
  Behavior on progress {
    NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
  }

  implicitWidth: Style.space(380)
  implicitHeight: root.expanded
    ? deckColumn.implicitHeight
    : front.implicitHeight + root.peekCount * Style.space(6)

  HoverHandler {
    id: hover
  }

  // The peeks are shapes, not cards: their text would read through the front
  // card's surface, and a deck is about the count and the newest message until
  // it opens.
  Repeater {
    model: root.expanded ? 0 : root.peekCount

    delegate: Rectangle {
      required property int index

      width: parent.width - (index + 1) * Style.space(8)
      height: front.implicitHeight
      x: (index + 1) * Style.space(4)
      y: (index + 1) * Style.space(6)
      z: -1 - index
      radius: Theme.cornerRadius
      color: Theme.surface
      border.width: Style.strokeWidth
      border.color: Theme.border
      opacity: 1 - root.progress
    }
  }

  NotificationCard {
    id: front

    width: parent.width
    height: implicitHeight
    visible: !root.expanded
    opacity: 1 - root.progress
    notification: root.count > 0 ? root.items[0] : null
    group: root.items
    replay: root.replay
    autoExpire: !root.paused
  }

  Column {
    id: deckColumn

    width: parent.width
    spacing: Style.space(8)
    visible: root.expanded
    opacity: root.progress

    Repeater {
      model: root.items

      delegate: NotificationCard {
        required property var modelData

        width: parent.width
        // Column positions children by their height, not their implicit height;
        // without this the opened deck drew every card at zero height.
        height: implicitHeight
        notification: modelData
        group: [modelData]
        replay: root.replay
        autoExpire: !root.paused
      }
    }
  }
}
