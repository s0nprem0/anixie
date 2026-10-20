import QtQuick
import ".."
import "."

// The on-screen display card: a glyph, a level bar and a state/value label.
Item {
  id: root

  property string icon: ""
  property int percent: 0
  property string valueText: ""
  property bool muted: false

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
          width: root.muted ? 0 : parent.width * root.percent / 100
          height: parent.height
          color: Theme.primary
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        // A fixed column keeps the card from resizing between "9%" and "100%"
        // or between a level and "Muted".
        width: Style.space(44)
        horizontalAlignment: Text.AlignRight
        text: root.valueText || (root.percent + "%")
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
