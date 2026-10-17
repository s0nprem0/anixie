import QtQuick
import ".."
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Workspace pills driven by Hyprland's event socket rather than by polling
// hyprctl: Hyprland.workspaces.values is a change-notifying list, so a switch
// redraws immediately instead of waiting out the poll interval.
Row {
  id: root
  spacing: Theme.gap

  property var entry: ({})

  readonly property var workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

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
  // reshuffle under the pointer while you drag windows between them.
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
  // Lua dispatch path some bars use is unavailable.
  function focus(id) {
    focusProc.command = ["hyprctl", "dispatch", "workspace", String(id)]
    focusProc.running = true
  }

  Process {
    id: focusProc
    running: false
  }

  Repeater {
    model: root.workspaceIds()

    delegate: Rectangle {
      id: pill
      required property int modelData

      readonly property bool focused: root.focusedId === modelData

      width: 22
      height: 22
      radius: 11
      color: focused ? Theme.primary : "transparent"
      border.color: focused ? Theme.primary : Theme.surface
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: pill.modelData === 10 ? "0" : String(pill.modelData)
        color: pill.focused ? Theme.bg : (root.occupied(pill.modelData) ? Theme.fg : Theme.muted)
        font.family: "JetBrains Mono"
        font.pixelSize: 11
        font.weight: pill.focused ? Font.DemiBold : Font.Normal
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focus(pill.modelData)
      }
    }
  }
}