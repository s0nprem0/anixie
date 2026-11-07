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

  // Size label, on a pill so it stays readable over bright content.
  Rectangle {
    x: root.host.selX
    y: Math.max(0, root.host.selY - Style.space(24))
    width: sizeText.implicitWidth + Style.space(12)
    height: sizeText.implicitHeight + Style.space(6)
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth
    visible: root.host.selW > 0 && root.host.selH > 0

    Text {
      id: sizeText
      anchors.centerIn: parent
      text: Math.round(root.host.selW) + " × " + Math.round(root.host.selH)
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
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

  // Keyboard path: arrows nudge the selection edge (Shift for ten
  // pixels), Enter captures, Esc cancels. The item takes focus on
  // open so these reach it; the window runs with exclusive focus.
  focus: true
  Component.onCompleted: forceActiveFocus()

  Keys.onPressed: function (event) {
    const step = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
    if (event.key === Qt.Key_Escape) { root.host.close(); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.host.selW >= 4 && root.host.selH >= 4) root.host.capture()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left) { root.host.endX -= step; event.accepted = true }
    else if (event.key === Qt.Key_Right) { root.host.endX += step; event.accepted = true }
    else if (event.key === Qt.Key_Up) { root.host.endY -= step; event.accepted = true }
    else if (event.key === Qt.Key_Down) { root.host.endY += step; event.accepted = true }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(24)
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Drag to select · hover window to snap · click for full screen · arrows nudge · Enter captures · right-click or Esc to cancel"
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }
}