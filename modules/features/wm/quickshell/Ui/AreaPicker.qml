pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Item {
  id: root

  readonly property var host: AreaPickerHost

  property bool dragging: false
  property bool hoverSnapped: false

  // Frozen frame background (if freeze mode).
  Image {
    anchors.fill: parent
    source: root.host.freeze && root.host.freezePath !== "" ? ("file://" + root.host.freezePath) : ""
    visible: root.host.freeze && root.host.freezePath !== ""
    fillMode: Image.PreserveAspectCrop
  }

  // Dim rectangles around the selection.
  Rectangle { x: 0; y: 0; width: parent.width; height: root.host.selY; color: Theme.curtain; opacity: 0.5 }
  Rectangle { x: 0; y: root.host.selY + root.host.selH; width: parent.width; height: Math.max(0, parent.height - (root.host.selY + root.host.selH)); color: Theme.curtain; opacity: 0.5 }
  Rectangle { x: 0; y: root.host.selY; width: root.host.selX; height: root.host.selH; color: Theme.curtain; opacity: 0.5 }
  Rectangle { x: root.host.selX + root.host.selW; y: root.host.selY; width: Math.max(0, parent.width - (root.host.selX + root.host.selW)); height: root.host.selH; color: Theme.curtain; opacity: 0.5 }

  // Selection border.
  Rectangle {
    x: root.host.selX; y: root.host.selY
    width: root.host.selW; height: root.host.selH
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

  // Hovered window label.
  Text {
    anchors.top: parent.top
    anchors.topMargin: Style.space(12)
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.host.hoveredWindow
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
    visible: root.host.hoveredWindow !== "" && !root.dragging
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.CrossCursor
    hoverEnabled: true

    onPressed: function (event) {
      if (event.button === Qt.RightButton) { root.host.close(); return }
      root.dragging = true
      root.host.startX = event.x
      root.host.startY = event.y
      root.host.endX = event.x
      root.host.endY = event.y
    }
    onPositionChanged: function (event) {
      if (root.dragging) {
        root.host.endX = event.x
        root.host.endY = event.y
      } else {
        // hover snapping
        const snapped = root.host.snapToWindow(event.x, event.y)
        root.hoverSnapped = snapped
      }
    }
    onReleased: function (event) {
      if (!root.dragging) return
      root.dragging = false
      if (root.host.selW < 4 || root.host.selH < 4) {
        // Bare click: if hovering a window, keep its rect; else whole monitor.
        if (!root.hoverSnapped) {
          root.host.startX = 0
          root.host.startY = 0
          root.host.endX = root.width
          root.host.endY = root.height
        }
      }
      root.host.capture()
    }
  }

  Keys.onEscapePressed: root.host.close()

  Text {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(24)
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Drag to select · hover window to snap · click for full screen · right-click or Esc to cancel"
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }
}