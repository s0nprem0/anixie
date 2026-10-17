pragma Singleton

import QtQuick
import ".."
import Quickshell
import Quickshell.Wayland

// One tooltip shared by every bar button. Each button hands over its text and
// itself as the subject; the window sits above that button and closes when the
// pointer leaves. A single window means the bar can never stack two tooltips.
QtObject {
  id: root

  // The bar's own window, set once at startup. The popup anchors to this rather
  // than to whichever button is hovered: PopupWindow resolves its anchor when
  // it is created, and at that point no button has been hovered, so anchoring
  // straight to the subject would leave it unanchored for good.
  property Item host: null

  property string text: ""
  property var source: null
  property bool shown: false

  function show(label, item) {
    root.text = String(label || "")
    root.source = item

    if (root.text === "" || !item) {
      delay.stop()
      root.shown = false
      return
    }

    delay.restart()
  }

  function hide() {
    delay.stop()
    root.shown = false
    root.text = ""
    root.source = null
  }

  // A tooltip that appears the instant the pointer crosses the bar is noise, so
  // it waits for the pointer to settle. Held as a property because a QtObject
  // has no default property for a bare child declaration to attach to.
  property Timer delay: Timer {
    interval: 450
    onTriggered: root.shown = true
  }

  readonly property rect subjectRect: {
    if (!root.source || !root.host) return Qt.rect(0, 0, 0, 0)

    const topLeft = root.source.mapToItem(root.host, 0, 0)
    return Qt.rect(topLeft.x, topLeft.y, root.source.width, root.source.height)
  }

  property PopupWindow window: PopupWindow {
    visible: root.shown && root.host !== null
    color: "transparent"
    anchor.item: root.host
    anchor.rect: root.subjectRect
    implicitWidth: Math.max(32, body.implicitWidth + 16)
    implicitHeight: body.implicitHeight + 10

    Rectangle {
      anchors.fill: parent
      radius: 6
      color: Theme.surface
      border.color: Theme.muted
      border.width: 1
    }

    Text {
      id: body
      anchors.centerIn: parent
      text: root.text
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}