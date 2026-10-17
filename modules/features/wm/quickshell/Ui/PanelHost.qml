pragma Singleton

import QtQuick
import ".."
import Quickshell
import Quickshell.Wayland

// One popup at a time for the whole bar, plus the invisible surface that
// dismisses it.
//
// A PopupWindow only receives input that lands on it, so without the curtain a
// click anywhere else would pass straight through to whatever is underneath and
// leave the panel stranded on screen. The curtain covers everything below the
// bar and swallows that click. It deliberately stops short of the bar itself, so
// the bar stays live and clicking a module still works.
QtObject {
  id: root

  // The bar's window, set once at startup, for the same reason TooltipHost needs
  // it: a popup resolves its anchor when it is created.
  property Item host: null

  // The bar button the panel belongs to.
  property var owner: null
  property bool shown: false

  function toggle(anchorItem, builder) {
    if (root.shown && root.owner === anchorItem) {
      root.close()
      return
    }
    root.show(anchorItem, builder)
  }

  function show(anchorItem, builder) {
    if (!anchorItem || !builder) return

    root.owner = anchorItem
    root.builder = builder

    // Reassigned even when unchanged, so reopening the same panel rebuilds its
    // contents instead of leaving whatever was there last.
    contentLoader.sourceComponent = null
    contentLoader.sourceComponent = builder
    root.shown = true
  }

  function close() {
    root.shown = false
    root.owner = null
    root.builder = null
  }

  property var builder: null

  // Taken from the bar's own window rather than from Quickshell.screens, whose
  // entries on this version expose only model and name.
  readonly property real screenWidth: root.host ? root.host.Screen.width : 1920
  readonly property real screenHeight: root.host ? root.host.Screen.height : 1080
  readonly property real barHeight: Style.bar.sizeHorizontal

  // Centred under the owning button, then pulled back inside the screen so a
  // button near either edge still opens a fully visible panel.
  readonly property rect panelRect: {
    if (!root.owner || !root.host) return Qt.rect(0, 0, 0, 0)

    const width = contentLoader.item ? contentLoader.item.implicitWidth : 320
    const left = root.owner.mapToItem(root.host, 0, 0).x
    const centre = left + root.owner.width / 2

    const margin = Style.space(8)
    const x = Math.max(margin, Math.min(Math.round(centre - width / 2), root.screenWidth - width - margin))

    return Qt.rect(x, root.barHeight, width, 0)
  }

  property PopupWindow curtain: PopupWindow {
    visible: root.shown
    color: "transparent"
    anchor.item: root.host
    // Gravity puts the window below the rect, so starting the rect at the bar's
    // full height leaves the bar itself uncovered.
    anchor.rect: Qt.rect(0, 0, root.screenWidth, root.barHeight)
    implicitWidth: root.screenWidth
    implicitHeight: root.screenHeight - root.barHeight

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: root.close()
    }
  }

  property PopupWindow panel: PopupWindow {
    id: panelWindow
    visible: root.shown
    color: "transparent"
    anchor.item: root.host
    anchor.rect: root.panelRect
    implicitWidth: contentLoader.item ? contentLoader.item.implicitWidth : 320
    implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

    Loader {
      id: contentLoader
      anchors.centerIn: parent
      sourceComponent: root.builder
    }
  }
}