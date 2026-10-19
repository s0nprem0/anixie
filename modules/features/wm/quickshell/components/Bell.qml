import QtQuick
import ".."
import "../Ui"
import "../panels"
import Quickshell

// A bell in the bar, which opens the notification history.
//
// It sits next to the silencing indicator rather than replacing it: silencing is
// a switch, history is a record, and neither does the other's job. While
// notifications are silenced the bell is dimmed rather than hidden, so the
// reason the popups stopped appearing is visible from the bar.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click, like every other panel.
  Component.onCompleted: PanelRegistry.register("notifications", readout, historyPanel)

  readonly property bool silenced: NotificationHost.doNotDisturb

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  // Declared as an id rather than built inline: `Component { ... }` is an object
  // declaration, so it cannot be passed as a call argument.
  Component {
    id: historyPanel
    Notifications {}
  }

  BarIconButton {
    id: readout

    anchors.centerIn: parent
    text: Util.bell
    // Dimmed rather than hidden: an absent bell would read as "no notifications
    // feature" instead of "notifications are silenced".
    dimmed: root.silenced
    active: !root.silenced
    tooltipText: root.silenced
      ? "Notification history · notifications are silenced"
      : "Notification history"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        // Read the list before it is drawn, so the panel never appears empty and
        // then fill itself in a moment later.
        NotificationStore.refresh()
        PanelRegistry.toggle("notifications")
      } else if (button === Qt.RightButton) {
        NotificationHost.toggle()
      }
    }
  }
}