import QtQuick
import ".."
import "."

// The on-screen display card: a glyph, then either a progress bar and a value,
// or a message. The message form is what a media key or a script uses; the
// progress form is what volume, microphone and brightness use.
Item {
  id: root

  property string icon: ""
  property string message: ""
  property bool hasProgress: true
  property int value: 0
  property int maxValue: 100
  property bool mediaOsd: false

  readonly property real ratio: root.maxValue > 0
    ? Math.max(0, Math.min(1, root.value / root.maxValue))
    : 0

  implicitWidth: content.implicitWidth + Style.space(28)
  implicitHeight: Style.space(36)

  Rectangle {
    anchors.fill: parent
    color: Theme.surface
    border.width: Style.strokeWidth
    border.color: Theme.border
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
        visible: root.hasProgress
        width: Style.space(120)
        height: Style.space(4)
        color: Theme.bg

        Rectangle {
          width: parent.width * root.ratio
          height: parent.height
          color: Theme.primary

          Behavior on width {
            NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter

        // A fixed column keeps the progress card from resizing between "9%"
        // and "100%" or between a level and "Muted". A notice has no such
        // number, so it takes its own width up to a readable cap.
        visible: root.message !== ""
        width: root.hasProgress
          ? Style.space(44)
          : Math.min(implicitWidth, Style.space(root.mediaOsd ? 320 : 220))
        horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
        text: root.message
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }
}
