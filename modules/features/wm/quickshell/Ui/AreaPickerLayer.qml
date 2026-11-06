pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// The area picker's full-output surface. On the Overlay layer, above notifications.
Item {
  PanelWindow {
    id: pickerWindow
    screen: (AreaPickerHost && AreaPickerHost.targetScreen)
      ? AreaPickerHost.targetScreen
      : ((Screens && Screens.focused) ? Screens.focused : null)

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    visible: (AreaPickerHost && AreaPickerHost.shown) || false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-area-picker"
    WlrLayershell.keyboardFocus: (AreaPickerHost && AreaPickerHost.shown)
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    AreaPicker {
      anchors.fill: parent
    }
  }
}