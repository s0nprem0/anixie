pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// A reusable full-screen click-catching surface.
//
// Used by popups that need to dismiss on a click anywhere outside their own
// card, including on outputs the popup surface itself does not cover. The
// curtain is a layer surface on the given layer; its MouseArea swallows the
// press and emits `pressed(screenName)` so the owner can decide what to close.
//
// `screens` is a list of ShellScreen objects (or items whose screen can be
// resolved). When an entry is an item rather than a screen, pass
// `resolveScreen: true` and the curtain resolves it via Screens.
Item {
  id: root

  // List of ShellScreen objects, or items to resolve when resolveScreen is set.
  property var screens: []

  // Whether entries in `screens` are items whose screen must be resolved.
  property bool resolveScreen: false

  property int wlrLayer: WlrLayer.Overlay
  property string namespace: "quickshell-curtain"
  property int keyboardFocus: WlrKeyboardFocus.None
  property int marginsTop: 0
  property int marginsBottom: 0
  property int marginsLeft: 0
  property int marginsRight: 0

  signal pressed(string screenName)

  visible: root.screens && root.screens.length > 0

  Variants {
    model: root.screens || []

    delegate: PanelWindow {
      required property var modelData

      readonly property string screenName: root.resolveScreen
        ? Screens.nameOf(modelData)
        : String(modelData && modelData.name ? modelData.name : "")
      readonly property var screenInfo: root.resolveScreen
        ? Screens.byName(screenName)
        : modelData

      screen: screenInfo
      visible: screenInfo !== null
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      margins.top: root.marginsTop
      margins.bottom: root.marginsBottom
      margins.left: root.marginsLeft
      margins.right: root.marginsRight

      WlrLayershell.layer: root.wlrLayer
      WlrLayershell.namespace: root.namespace
      WlrLayershell.keyboardFocus: root.keyboardFocus

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.pressed(screenName)
      }
    }
  }
}