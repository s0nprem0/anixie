import QtQuick
import ".."

Item {
  id: root

  property string label: ""
  property var colors: ({})
  property bool selected: false
  property bool favorite: false
  property string mode: "dark"

  signal clicked()
  signal favoriteToggled()

  readonly property bool panelFocusable: true
  readonly property var swatches: [
    colors.background || Theme.bg,
    colors.surface || Theme.surface,
    colors.primary || Theme.primary,
    colors.accent || Theme.accent,
    colors.accentAlt || Theme.accentAlt,
    colors.foreground || Theme.fg
  ]

  function activate() {
    root.clicked()
  }

  function keyStep(direction) {
    return false
  }

  implicitWidth: labelText.implicitWidth + 150
  implicitHeight: Math.max(labelText.implicitHeight, Style.space(24))

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: root.selected
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.selectedFillAlpha)
      : (mouse.containsMouse ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha) : "transparent")
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }

  Row {
    id: swatchRow
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Repeater {
      model: root.swatches
      delegate: Rectangle {
        required property var modelData
        width: Style.space(8)
        height: width
        radius: Theme.cornerRadius
        color: modelData
      }
    }
  }

  Text {
    id: labelText
    anchors.left: swatchRow.right
    anchors.leftMargin: Style.space(8)
    anchors.right: stateRow.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.selected ? Theme.accent : Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: root.selected ? Font.DemiBold : Font.Normal
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  Row {
    id: stateRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Text {
      visible: root.mode === "light"
      text: Util.sun
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      text: root.favorite ? Util.star : Util.starOutline
      color: root.favorite ? Theme.yellow : Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function (event) {
      if (event.button === Qt.RightButton) root.favoriteToggled()
      else root.clicked()
    }
  }
}
