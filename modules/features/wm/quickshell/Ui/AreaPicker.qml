pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// The area picker's contents: a dimmed overlay with a clear selection rectangle
// and a drag to redefine it. Fills the whole window; the host owns the state.
Item {
  id: root

  readonly property var host: AreaPickerHost

  property bool dragging: false

  // Dim rectangles around the selection (top/bottom/left/right) so the chosen
  // region stays bright without needing a mask effect.
  Rectangle {
    x: 0; y: 0
    width: parent.width
    height: root.host.selY
    color: Theme.curtain
    opacity: 0.5
  }
  Rectangle {
    x: 0; y: root.host.selY + root.host.selH
    width: parent.width
    height: Math.max(0, parent.height - (root.host.selY + root.host.selH))
    color: Theme.curtain
    opacity: 0.5
  }
  Rectangle {
    x: 0; y: root.host.selY
    width: root.host.selX
    height: root.host.selH
    color: Theme.curtain
    opacity: 0.5
  }
  Rectangle {
    x: root.host.selX + root.host.selW; y: root.host.selY
    width: Math.max(0, parent.width - (root.host.selX + root.host.selW))
    height: root.host.selH
    color: Theme.curtain
    opacity: 0.5
  }

  // Selection border.
  Rectangle {
    x: root.host.selX
    y: root.host.selY
    width: root.host.selW
    height: root.host.selH
    color: "transparent"
    border.color: Theme.primary
    border.width: Style.strokeWidth * 2
    radius: Theme.cornerRadius
  }

  // Size label.
  Text {
    x: root.host.selX
    y: Math.max(0, root.host.selY - Style.space(20))
    text: Math.round(root.host.selW) + " × " + Math.round(root.host.selH)
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
    visible: root.host.selW > 0 && root.host.selH > 0
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.CrossCursor

    onPressed: function (event) {
      if (event.button === Qt.RightButton) {
        root.host.close()
        return
      }
      root.dragging = true
      root.host.startX = event.x
      root.host.startY = event.y
      root.host.endX = event.x
      root.host.endY = event.y
    }
    onPositionChanged: function (event) {
      if (!root.dragging) return
      root.host.endX = event.x
      root.host.endY = event.y
    }
    onReleased: function (event) {
      if (!root.dragging) return
      root.dragging = false
      if (root.host.selW < 4 || root.host.selH < 4) {
        // Bare click: take the whole monitor.
        root.host.startX = 0
        root.host.startY = 0
        root.host.endX = root.width
        root.host.endY = root.height
      }
      root.host.capture()
    }
  }

  Keys.onEscapePressed: root.host.close()

  // Hint.
  Text {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(24)
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Drag to select · click for full screen · right-click or Esc to cancel"
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }
}