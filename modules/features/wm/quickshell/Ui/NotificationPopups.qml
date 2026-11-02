import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// Notification popups. Top right, over everything, and taking no keyboard: a
// notification is there to be read, not typed into. Sized to its stack, so an
// empty one leaves no window behind to swallow clicks. The output choice is
// read from NotificationHost, which the panel can change at runtime.
Item {
  id: root

  // The history panel is narrower than a toast and sits over the same corner.
  // Leaving the toasts mapped made them peek out from behind it as a sliver;
  // hide the stack while the panel owns that corner, then let it return.
  readonly property bool historyOpen: {
    const panels = PanelHost.openPanels
    if (!panels || typeof panels.count !== "number") return false
    for (let i = 0; i < panels.count; i++) {
      const panel = panels.get ? panels.get(i) : null
      if (panel && String(panel.name) === "notifications") return true
    }
    return false
  }

  Variants {
    model: {
      const mode = NotificationHost.displayMode
      if (mode === "all") return Quickshell.screens
      if (mode === "specific") {
        const screen = Screens.byName(NotificationHost.displayName)
        return screen ? [screen] : []
      }
      return Screens.focused ? [Screens.focused] : []
    }

    delegate: PanelWindow {
      id: notificationWindow
      required property var modelData
      screen: modelData

      // The bar edge to keep clear of on this output, or none if it has no bar.
      readonly property string barPosition: PanelHost.barEdgeOn(modelData ? modelData.name : "")

      anchors.top: true
      anchors.right: true

      // Clear of the bar on whichever edge it is: the cards sit under a top bar
      // and beside a right one, rather than over it.
      margins.top: notificationWindow.barPosition === "top"
        ? PanelHost.barExtent + Style.space(10)
        : Style.space(10)
      margins.right: notificationWindow.barPosition === "right"
        ? PanelHost.barExtent + Style.space(10)
        : Style.space(10)

      // Never claim more usable space than the output actually has: a very small
      // output must be allowed to report (near-)zero rather than a forced floor.
      readonly property real _availableWidth: Math.max(0,
        (modelData ? modelData.width : 0) - notificationWindow.margins.right - Style.space(10))
      readonly property real _availableHeight: Math.max(0,
        (modelData ? modelData.height : 0) - notificationWindow.margins.top - Style.space(10))

      // The card's own width (NotificationDeck's implicitWidth), not the
      // column's: the decks size themselves to the column, which sizes itself
      // to this window, so measuring the column collapsed the window to 1px.
      implicitWidth: Math.min(Style.space(380), notificationWindow._availableWidth)
      implicitHeight: Math.min(notificationColumn.implicitHeight, notificationWindow._availableHeight)

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      // Visibility is derived from the deck data actually shown by the Repeater,
      // rather than independently from NotificationHost.tracked.length.
      readonly property bool hasNotifications: notificationWindow.decks.length > 0
      // Unmapped whenever there is nothing to show, fullscreen or not: an empty
      // surface still sits on the Overlay layer and takes the clicks under it.
      visible: !root.historyOpen && notificationWindow.hasNotifications

      // A burst — a mailing list, a chat backlog — should not draw a column taller
      // than the screen with the last cards unreachable. The newest few are shown,
      // the rest are counted, and the history panel has them all.
      readonly property int maxCards: NotificationHost.replaying || NotificationHost.restoring ? 10 : 4
      readonly property var decks: {
        if (NotificationHost.replaying) {
          const replay = Array.isArray(NotificationHost.replayEntries)
            ? NotificationHost.replayEntries
            : []
          const out = []
          for (const entry of replay) {
            if (entry) out.push({ items: [entry], restored: false })
          }
          return out
        }

        const out = []
        if (NotificationHost.restoring) {
          const restored = Array.isArray(NotificationHost.restoredEntries)
            ? NotificationHost.restoredEntries
            : []
          for (const entry of restored) {
            if (entry) out.push({ items: [entry], restored: true })
          }
        }
        const groups = Array.isArray(NotificationHost.groups) ? NotificationHost.groups : []
        for (const group of groups) {
          const items = group && Array.isArray(group.items) ? group.items : []
          if (items.length === 0) continue
          out.push({ items: items, restored: false })
        }
        return out
      }
      readonly property var shownDecks: notificationWindow.decks.slice(0, notificationWindow.maxCards)
      readonly property int hiddenCount: Math.max(0, notificationWindow.decks.length - notificationWindow.shownDecks.length)

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-notifications"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Flickable {
        id: notificationFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: notificationColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {}

        Column {
          id: notificationColumn

          width: notificationFlick.width
          spacing: Style.space(8)

          Repeater {
            model: notificationWindow.shownDecks

            delegate: NotificationDeck {
              required property var modelData

              items: modelData.items
              replay: NotificationHost.replaying || modelData.restored === true
              forceExpanded: NotificationHost.replaying || modelData.restored === true
              paused: root.historyOpen
            }
          }

          // (overflow indicator moved out of the scroll content so it stays
          // visible even when the stack is taller than the output)
        }
      }

      // Overflow indicator: reads as a stack counter rather than another card,
      // and stays pinned over the bottom of the popup when the stack scrolls.
      Rectangle {
        visible: notificationWindow.hiddenCount > 0
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Style.space(10)
        z: 10
        implicitWidth: overflowLabel.implicitWidth + Style.space(12)
        implicitHeight: overflowLabel.implicitHeight + Style.space(6)
        radius: Theme.cornerRadius
        color: Theme.surface
        border.width: Style.strokeWidth
        border.color: Theme.border

        Text {
          id: overflowLabel
          anchors.centerIn: parent
          text: "+" + notificationWindow.hiddenCount + " more"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
