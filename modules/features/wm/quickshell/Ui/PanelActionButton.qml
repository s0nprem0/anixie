import QtQuick
import ".."

// A panel row you can click. Looks like a PanelRow — a label on the left, a value
// on the right — but the whole row is the button, with the row's hover fill to
// say so.
//
// Panels use this for the rows that lead somewhere or do something rather than
// showing a value: "Sign out", "Turn off Wi-Fi", "Open settings". A plain
// PanelRow looks identical until you move the pointer over it, which is the
// problem this solves.
//
// `navigational: false` drops the chevron, for the ones that act rather than
// lead somewhere — "Disconnect", "Scan for networks", "Clear history". Same row,
// same hover, without a promise to go somewhere it does not go.
Item {
  id: root

  property string label: ""
  property string value: ""
  property string glyph: ""
  property bool danger: false
  property bool navigational: true
  property bool outlined: false
  property bool available: true

  signal clicked()

  Accessible.role: Accessible.Button
  Accessible.name: root.label
  Accessible.description: root.value !== "" ? root.value : root.label

  readonly property bool panelFocusable: root.available

  function activate() {
    if (!root.available) return
    root.clicked()
  }

  function keyStep(direction) {
    return false
  }

  readonly property color foreground: root.danger ? Theme.danger : Theme.fg
  readonly property real horizontalPadding: Style.space(6)
  readonly property real verticalPadding: Style.space(4)

  implicitWidth: parent ? parent.width : (labelText.implicitWidth + valueText.implicitWidth + chevronText.implicitWidth + Style.space(20))
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight, Style.space(26))

  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.cornerRadius
    color: mouse.pressed && root.available
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
          Style.control.pressedFillAlpha)
      : (mouse.containsMouse && root.available
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
            root.outlined ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
        : "transparent")
    border.color: root.outlined && root.available ? root.foreground : "transparent"
    border.width: root.outlined ? Style.strokeWidth : 0
    opacity: root.available ? 1 : Style.disabledOpacity
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: root.horizontalPadding + 2
    anchors.right: valueText.visible
      ? valueText.left
      : (root.navigational ? chevron.left : parent.right)
    anchors.rightMargin: valueText.visible
      ? Style.space(6)
      : (root.navigational ? Style.space(4) : root.horizontalPadding + 2)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Text {
    id: valueText
    anchors.right: root.navigational ? chevron.left : parent.right
    anchors.rightMargin: root.navigational ? Style.space(4) : root.horizontalPadding + 2
    anchors.verticalCenter: parent.verticalCenter
    visible: root.value !== ""
    width: Math.min(implicitWidth, Math.max(40, parent.width * 0.4))
    text: root.value
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Item {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding + 2
    anchors.verticalCenter: parent.verticalCenter
    width: root.navigational ? chevronText.implicitWidth : 0
    height: chevronText.implicitHeight
  }

  Text {
    id: chevronText
    anchors.centerIn: chevron
    visible: root.navigational
    text: "›"
    color: mouse.pressed && root.available
      ? root.foreground
      : (mouse.containsMouse && root.available ? root.foreground : Theme.muted)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (!root.available) return
      root.clicked()
    }
  }

  clip: true
}
