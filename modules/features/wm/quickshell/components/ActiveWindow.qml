import QtQuick
import ".."
import "../Ui"
import Quickshell.Wayland

// Title of the focused window, read from the compositor rather than from
// Hyprland, so it also covers windows from other toolkits. Click to focus,
// middle or right to close — the same gestures the reference design uses.
BarWidget {
  id: root

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string title: toplevel ? (toplevel.title || "") : ""
  readonly property int maxLabelWidth: Number(setting("maxWidth", 200))

  visible: title !== "" && !root.vertical
  implicitWidth: Math.min(maxLabelWidth, label.implicitWidth) + 16
  implicitHeight: barSize

  // A title that changes width every few seconds would otherwise make the rest
  // of the bar twitch; ease into the new width instead.
  Behavior on implicitWidth {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    x: 8
    width: Math.min(root.maxLabelWidth, implicitWidth)
    text: root.title
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (mouse) {
      if (!root.toplevel) return

      if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) root.toplevel.close()
      else root.toplevel.activate()
    }
  }
}