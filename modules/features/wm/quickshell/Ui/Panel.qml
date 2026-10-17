import QtQuick
import ".."

// The card a panel's contents sit in: a rounded surface with a title row, then
// whatever rows and controls the panel puts below it.
Item {
  id: root

  // Children a panel declares land in the content column rather than on the
  // card itself, which is the whole point of the type.
  default property alias content: body.data

  property string title: ""
  property int maxWidth: Style.space(340)

  implicitWidth: Math.min(maxWidth, Math.max(header.implicitWidth, body.implicitWidth) + padding * 2)
  implicitHeight: padding * 2
    + (header.visible ? header.implicitHeight + Style.space(10) : 0)
    + body.implicitHeight

  readonly property int padding: Style.space(14)

  // Row width for panel contents. Exposed as a property because `body` is an id
  // local to this file and is not reachable from the panels that use it.
  readonly property real contentWidth: width - padding * 2

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.muted
    border.width: 1
  }

  Text {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.padding
    anchors.leftMargin: root.padding
    anchors.rightMargin: root.padding
    visible: root.title !== ""
    text: root.title
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.DemiBold
  }

  Column {
    id: body
    anchors.top: header.visible ? header.bottom : parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: header.visible ? Style.space(10) : root.padding
    anchors.leftMargin: root.padding
    anchors.rightMargin: root.padding
    spacing: Style.space(8)
  }
}