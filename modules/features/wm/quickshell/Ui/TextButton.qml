import QtQuick
import ".."

// A word that acts, for the buttons that live inside a row rather than taking
// one of their own: "Connect" and "Forget" under a network, "disconnect" beside
// a VPN. A PanelActionButton would stack these as full-width rows, which is not
// what a row of alternatives is.
//
// Muted at rest and lit on hover, the same step the panel's rows make. `active`
// is for the one that says what is already the case — the connection in use, an
// automatic-connect that is on — so the state is readable without reading the
// label twice.
Item {
  id: root

  property string label: ""
  property bool active: false
  property bool danger: false
  property bool available: true
  property string tooltipText: ""

  signal clicked()

  // ---- the keyboard ----
  //
  // A button, so Return is the click and the sideways keys mean nothing.
  readonly property bool panelFocusable: root.available

  function activate() {
    root.clicked()
  }

  function keyStep(direction) {
    return false
  }

  readonly property color resting: root.danger
    ? Theme.danger
    : (root.active ? Theme.accent : Theme.muted)

  implicitWidth: labelText.implicitWidth + Style.space(12)
  implicitHeight: Math.max(labelText.implicitHeight, Style.space(20))
  width: implicitWidth
  height: implicitHeight
  opacity: root.available ? 1 : Style.disabledOpacity

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.containsMouse && root.available
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
      : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    color: mouse.containsMouse && root.available
      ? (root.danger ? Theme.danger : Theme.fg)
      : root.resting
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.weight: root.active ? Font.DemiBold : Font.Normal
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: if (root.tooltipText !== "") TooltipHost.show(root.tooltipText, root)
    onExited: if (root.tooltipText !== "") TooltipHost.hide(root)
    onClicked: root.clicked()
  }
}
