import QtQuick
import Quickshell
import Quickshell.Wayland

// The clipboard's full-output surface, on the Overlay layer so it covers
// notifications the same way the picker does.
Item {
  PanelWindow {
    id: clipboardWindow
    screen: Screens.focused

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    visible: ClipboardHost.shown || clipboard.reveal > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: ClipboardHost.shown
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Clipboard {
      id: clipboard
      anchors.fill: parent
    }
  }
}
