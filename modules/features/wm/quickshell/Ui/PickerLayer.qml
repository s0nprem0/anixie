pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

// The picker's full-output surface. On the Overlay layer, above notifications,
// so a picker opened while something is being notified covers it.
Item {
  // The picker. Covers the whole output and takes the keyboard for as long as it
  // is up. On the Overlay layer, above the notifications.
  PanelWindow {
    id: pickerWindow
    screen: Screens && Screens.focused ? Screens.focused : null

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Mapped while shown and for as long as the card is still fading
    visible: (PickHost && PickHost.shown) || (picker && picker.reveal > 0)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-picker"
    WlrLayershell.keyboardFocus: (PickHost && PickHost.shown)
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Picker {
      id: picker
      anchors.fill: parent
    }
  }
}
