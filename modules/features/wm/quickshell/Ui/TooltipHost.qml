pragma Singleton

import QtQuick
import ".."
import Quickshell
import Quickshell.Wayland

// One tooltip shared by every bar button, owned here rather than by each button.
// A button calls show() on enter and hide() on exit; the rules below are what
// keep exactly one tooltip on screen and stop it being stranded.
QtObject {
  id: root

  property var tooltipTarget: null
  property string tooltipText: ""
  property bool tooltipShown: false

  // Bumped for every show and hide. A scheduled show records the number it was
  // issued with and gives up if it no longer matches, so a tooltip pending for
  // a button you have already left cannot appear.
  property int tooltipRequest: 0
  property int scheduledFor: -1

  // A button counts as hovered only if it is actually on screen. Modules hide
  // themselves — the volume slot disappears when there is no output device —
  // and a tooltip must not open for, or stick to, something invisible.
  function targetHovered(target) {
    return !!target
      && target.visible !== false
      && target.opacity !== 0
      && target.tooltipHovered === true
  }

  function clear() {
    showDelay.stop()
    root.tooltipTarget = null
    root.tooltipText = ""
    root.tooltipShown = false
  }

  function show(label, target) {
    // Cancels any show still waiting on the timer.
    root.clear()

    if (!root.targetHovered(target) || !label) {
      root.tooltipRequest += 1
      return
    }

    root.tooltipRequest += 1
    root.scheduledFor = root.tooltipRequest
    root.tooltipTarget = target
    root.tooltipText = String(label)
    showDelay.restart()
  }

  // Scoped to a target so that leaving one button does not tear down a tooltip
  // that another button has already claimed.
  function hide(target) {
    if (root.tooltipTarget !== target) return
    root.tooltipRequest += 1
    root.clear()
  }

  // A tooltip that appears the instant the pointer crosses the bar is noise, so
  // it waits for the pointer to settle. Held as a property because a QtObject
  // has no default property for a bare child declaration to attach to.
  property Timer showDelay: Timer {
    interval: 400
    onTriggered: {
      // Superseded while waiting: a newer show or a hide came and went.
      if (root.tooltipRequest !== root.scheduledFor) return

      if (root.targetHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clear()
    }
  }

  // A button can hide or dim itself while the pointer is still resting on it,
  // in which case onExited never arrives and the tooltip would hang over
  // nothing. Re-check while on screen so that case clears itself.
  property Timer watch: Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: {
      if (!root.targetHovered(root.tooltipTarget)) root.hide(root.tooltipTarget)
    }
  }

  // The tooltip is positioned when it is shown and does not then follow a button
  // that moves. Quickshell repositions a popup only on its own anchor or size
  // changes, and the way to ask for one — ProxyPopupWindow.reposition — is a
  // private slot, so QML cannot call it. A TransformWatcher was tried for this
  // and only threw on every layout change. In practice a tooltip is up for well
  // under a second, so it is placed where the button was when it appeared.
  property PopupWindow window: PopupWindow {
    visible: root.tooltipShown
      && root.tooltipTarget !== null
      && root.tooltipText !== ""
      && root.targetHovered(root.tooltipTarget)
    color: "transparent"

    // The button itself, with no explicit rect: PopupAnchor maps the anchor from
    // the item in C++ on every reposition, so it stays right as the button moves.
    // Computing the rect in QML with mapToItem cannot do that — mapToItem is a
    // plain function call, so the binding is never told that anything moved,
    // which is the failure Quickshell documents for coordinate mapping functions
    // in a binding to this property.
    anchor.item: root.tooltipTarget

    // Below the button, never across it. The defaults (edges Top|Left, gravity
    // Bottom|Right) put the popup's top-left on the rect's top-left, so a rect
    // taken from the button drew the tooltip over the button itself. Being its
    // own surface, the tooltip took the pointer with it, the button saw hover
    // lost and dismissed the tooltip, hover came back, and it opened again — the
    // flicker. Anchoring to the rect's bottom edge and growing downward starts it
    // clear of the button.
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    implicitWidth: Math.ceil(body.implicitWidth) + 20
    implicitHeight: Math.ceil(body.implicitHeight) + 14

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.surface
      border.color: Theme.muted
      border.width: 1
    }

    Text {
      id: body
      anchors.centerIn: parent
      text: root.tooltipText
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}