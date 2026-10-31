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

  Accessible.role: root.hasProgress ? Accessible.ProgressBar : Accessible.StaticText
  Accessible.name: root.message !== ""
    ? root.message
    : (root.hasProgress ? (root.value + " of " + root.maxValue) : root.icon)
  Accessible.description: root.hasProgress
    ? (root.message !== "" ? root.message : (root.value + " of " + root.maxValue))
    : root.message

  readonly property real _maxWidth: Math.min(
    Style.space(root.mediaOsd ? 360 : 240),
    (root.Screen ? root.Screen.width : 1920) - Style.space(40))
  readonly property real _preferredTrackWidth: Style.space(140)
  readonly property real _minimumTrackWidth: Style.space(60)

  // A notice with two words should still look like the OSD, not like a tiny
  // label that happened to float in. Levels are already wider than this.
  implicitWidth: Math.min(_maxWidth, Math.max(Style.space(180),
    root.hasProgress
      ? (Style.space(24) + Style.space(10) + _preferredTrackWidth
         + Style.space(10) + Style.space(44) + Style.space(28))
      : (Style.space(24) + Style.space(10)
         + Math.min(messageMetrics.advanceWidth, Style.space(root.mediaOsd ? 320 : 220))
         + Style.space(28))))
  implicitHeight: Style.space(36)

  width: Math.min(implicitWidth, root.parent ? root.parent.width : implicitWidth)

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
        width: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        text: root.icon
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasProgress
        width: Math.max(root._minimumTrackWidth,
          (root.width - Style.space(24) - Style.space(10) - Style.space(44)
           - Style.space(10) - Style.space(28)))
        height: Style.space(6)
        radius: height / 2
        color: Theme.separator
        clip: true

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * root.ratio))
          height: parent.height
          radius: parent.radius
          color: Theme.primary

          Behavior on width {
            NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic }
          }
        }
      }

      // Measuring outside the Text avoids the width -> implicitWidth -> width
      // loop an elided Text creates when it sizes itself to its own content.
      TextMetrics {
        id: messageMetrics
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        text: root.message
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter

        // A fixed column keeps the progress card from resizing between "9%"
        // and "100%" or between a level and "Muted". A notice has no such
        // number, so it takes its measured width up to a readable cap.
        visible: root.message !== ""
        width: root.hasProgress
          ? Style.space(44)
          : Math.min(messageMetrics.advanceWidth, Style.space(root.mediaOsd ? 320 : 220))
        horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
        text: root.message
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }
}
