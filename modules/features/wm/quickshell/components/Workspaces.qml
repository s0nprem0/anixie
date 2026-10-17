import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Workspace entries driven by Hyprland's event socket rather than by polling
// hyprctl: Hyprland.workspaces.values is a change-notifying list, so a switch
// repaints immediately instead of waiting out a poll interval.
BarWidget {
  id: root

  readonly property var workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  // A wheel notch moves one workspace along the row; a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function workspaceIds() {
    const ids = []
    for (let i = 0; i < root.workspaces.length; i++) {
      const id = root.workspaces[i].id
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function (a, b) {
      return a - b
    })
    return ids
  }

  // An empty workspace is dimmed rather than hidden, so the row does not
  // reshuffle under the pointer while windows are dragged between them.
  function occupied(id) {
    for (let i = 0; i < root.workspaces.length; i++) {
      if (root.workspaces[i].id === id) {
        const workspace = root.workspaces[i]
        return workspace.toplevels ? workspace.toplevels.values.length > 0 : false
      }
    }
    return false
  }

  // Plain hyprctl dispatch on purpose: this machine runs hyprlang, where the
  // Lua dispatch path is unavailable.
  function focus(id) {
    focusProc.command = ["hyprctl", "dispatch", "workspace", String(id)]
    focusProc.running = true
  }

  function scroll(delta) {
    const wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a long swipe stops on the
    // last workspace instead of jumping back to the first.
    const ids = root.workspaceIds()
    const index = ids.indexOf(root.focusedId)
    if (index === -1) return

    const target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focus(target)
  }

  Process {
    id: focusProc
    running: false
  }

  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  Row {
    id: row
    anchors.centerIn: parent

    Repeater {
      model: root.workspaceIds()

      delegate: WidgetButton {
        id: button
        required property int modelData

        readonly property bool focused: root.focusedId === modelData

        text: button.modelData === 10 ? "0" : String(button.modelData)
        active: button.focused
        dimmed: !button.focused && !root.occupied(button.modelData)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: Style.space(20)
        fixedHeight: Style.bar.sizeHorizontal
        tooltipText: "Workspace " + button.modelData

        onPressed: function (button_) {
          if (button_ !== Qt.LeftButton) return
          root.focus(button.modelData)
        }
        onWheelMoved: function (delta) {
          root.scroll(delta)
        }
      }
    }
  }
}