import QtQuick
import Quickshell
import Quickshell.Wayland

// The picker's full-output surface. On the Overlay layer, above notifications,
// so a picker opened while something is being notified covers it.
Item {
  // The picker. Covers the whole output and takes the keyboard for as long as it
  // is up, for the same reason the polkit prompt does: it is a surface you type
  // into, and everything on it has to be reachable without the mouse.
  //
  // On the Overlay layer, above the notifications — a picker opened while
  // something is being notified should cover it, not be covered by it.
  PanelWindow {
    id: pickerWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Mapped while shown and for as long as the card is still fading, which is
    // the same arrangement the OSD uses: unmapping on `shown` alone would cut
    // the fade off on its first frame.
    visible: PickHost.shown || picker.reveal > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-picker"
    WlrLayershell.keyboardFocus: PickHost.shown
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Picker {
      id: picker
      anchors.fill: parent
    }
  }
}
