import QtQuick
import ".."
import "."

// The on-screen display card: a glyph, a bar and a percentage.
Item {
  id: root

  property string icon: ""
  property int percent: 0

  implicitWidth: content.implicitWidth + Style.space(28)
  implicitHeight: Style.space(36)

  Rectangle {
    anchors.fill: parent
    color: Theme.surface
    border.width: 1
    border.color: Theme.muted
    radius: Theme.cornerRadius

    Row {
      id: content

      anchors.centerIn: parent
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(120)
        height: Style.space(4)
        color: Theme.bg

        Rectangle {
          width: parent.width * root.percent / 100
          height: parent.height
          color: Theme.primary
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.percent + "%"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
