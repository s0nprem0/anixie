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
    : (root.hasProgress ? (root.value + " of " + root.maxValue) : (root.icon !== "" ? root.icon : "OSD"))
  Accessible.description: root.hasProgress
    ? (root.message !== "" ? root.message : (root.value + " of " + root.maxValue))
    : root.message
  // (Accessible.value/maximumValue are not supported by this Qt version)

  readonly property real availableWidth: {
    const screenWidth = (root.Screen && root.Screen.width) ? Number(root.Screen.width) : 0
    if (Number.isFinite(screenWidth) && screenWidth > 0) return screenWidth
    return Style.space(root.mediaOsd ? 360 : 240)
  }

  readonly property real preferredMaxWidth: Style.space(root.mediaOsd ? 360 : 240)
  readonly property real maxWidth: Math.min(root.preferredMaxWidth, Math.max(Style.space(120), root.availableWidth - Style.space(16)))

  // Horizontal padding so the glyph and the text never touch the card edge.
  readonly property real pad: Style.space(12)

  readonly property real iconWidth: Style.space(24)
  readonly property real messageWidth: root.hasProgress
    ? Style.space(44)
    : Math.min(Style.space(root.mediaOsd ? 320 : 220),
        Math.max(Style.space(60), root.availableWidth - root.iconWidth - Style.space(48)))
  readonly property real preferredTrackWidth: Style.space(140)
  readonly property real trackWidth: root.hasProgress
    ? Math.max(0, Math.min(root.preferredTrackWidth,
        root.maxWidth - root.iconWidth - Style.space(10) - root.messageWidth - Style.space(10) - root.pad * 2))
    : 0

  implicitWidth: Math.min(root.maxWidth, Math.max(Style.space(120),
    root.hasProgress
      ? (root.iconWidth + Style.space(10) + root.trackWidth + Style.space(10) + root.messageWidth + root.pad * 2)
      : (root.iconWidth + Style.space(10) + root.messageWidth + root.pad * 2)))
  implicitHeight: Style.space(36)

  Rectangle {
    anchors.fill: parent
    color: Theme.surface
    border.width: Style.strokeWidth
    border.color: Theme.border
    radius: Theme.cornerRadius

    Row {
      id: content

      anchors.fill: parent
      anchors.margins: root.pad
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconWidth
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
        width: root.trackWidth
        height: Style.space(6)
        radius: Theme.cornerRadius
        color: Theme.separator
        clip: true

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * root.ratio))
          height: parent.height
          radius: Theme.cornerRadius
          color: Theme.primary

          Behavior on width {
            enabled: !Style.reduceMotion
            NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter

        visible: root.message !== ""
        width: root.messageWidth
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