import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
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
    for (let i = 0; i < panels.count; i++) {
      if (String(panels.get(i).name) === "notifications") return true
    }
    return false
  }

  Variants {
    model: NotificationHost.displayMode === "all"
      ? Quickshell.screens
      : (NotificationHost.displayMode === "specific" && Screens.byName(NotificationHost.displayName)
        ? [Screens.byName(NotificationHost.displayName)]
        : (Screens.focused ? [Screens.focused] : []))

    delegate: PanelWindow {
      id: notificationWindow
      required property var modelData
      screen: modelData

      anchors.top: true
      anchors.right: true

      // Clear of the bar on whichever edge it is: the cards sit under a top bar
      // and beside a right one, rather than over it.
      margins.top: BarContext.position === "top"
        ? Style.bar.sizeHorizontal + Style.space(10)
        : Style.space(10)
      margins.right: BarContext.position === "right"
        ? Style.bar.sizeVertical + Style.space(10)
        : Style.space(10)

      implicitWidth: notificationColumn.implicitWidth
      implicitHeight: notificationColumn.implicitHeight

      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      // Step aside over a fullscreen window when there is nothing to show, so
      // the fullscreen surface can be scanned out directly. A notification brings
      // the popup back over it, the way a toast should.
      readonly property bool fullscreenOnOutput: {
        if (!NotificationHost.fullscreenStepAside) return false
        const name = String(modelData.name)
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (const workspace of list) {
          if (workspace.monitor && String(workspace.monitor.name) === name && workspace.hasFullscreen) return true
        }
        return false
      }
      visible: !root.historyOpen
        && (NotificationHost.tracked.length > 0 || NotificationHost.replaying
          || NotificationHost.restoring || !notificationWindow.fullscreenOnOutput)

      // A burst — a mailing list, a chat backlog — should not draw a column taller
      // than the screen with the last cards unreachable. The newest few are shown,
      // the rest are counted, and the history panel has them all.
      readonly property int maxCards: NotificationHost.replaying || NotificationHost.restoring ? 10 : 4
      readonly property var decks: {
        if (NotificationHost.replaying) {
          return NotificationHost.replayEntries.map(function (entry) {
            return { items: [entry], restored: false }
          })
        }

        const out = []
        if (NotificationHost.restoring) {
          for (const entry of NotificationHost.restoredEntries) out.push({ items: [entry], restored: true })
        }
        for (const group of NotificationHost.groups) out.push({ items: group.items, restored: false })
        return out
      }
      readonly property var shownDecks: notificationWindow.decks.slice(0, notificationWindow.maxCards)
      readonly property int hiddenCount: Math.max(0, notificationWindow.decks.length - notificationWindow.shownDecks.length)

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-notifications"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Column {
        id: notificationColumn

        anchors.fill: parent
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

        Text {
          visible: notificationWindow.hiddenCount > 0
          height: implicitHeight
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
