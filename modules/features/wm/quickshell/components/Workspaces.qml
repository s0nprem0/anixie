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

  // Each bar shows its own monitor's workspaces. With more than one output the
  // global list is misleading: a row full of another display's workspaces on
  // this one, with the highlight on a workspace that is not even here.
  readonly property string screenName: root.Screen ? String(root.Screen.name) : ""

  readonly property var workspaces: {
    const all = Hyprland.workspaces ? Hyprland.workspaces.values : []
    if (root.screenName === "") return all

    const out = []
    for (let i = 0; i < all.length; i++) {
      const monitor = all[i].monitor
      if (!monitor || String(monitor.name) === root.screenName) out.push(all[i])
    }
    return out
  }

  // The workspace showing on this monitor, which is not necessarily the
  // globally focused one — the pointer can be on another display.
  readonly property var activeWorkspace: {
    for (let i = 0; i < root.workspaces.length; i++) {
      if (root.workspaces[i].active) return root.workspaces[i]
    }
    return null
  }

  readonly property int focusedId: root.activeWorkspace ? root.activeWorkspace.id : -1

  // The first five slots are always shown, whether or not a workspace has been
  // created yet, so the row does not reshuffle as windows come and go. Any
  // workspace beyond them is appended when it exists. Clicking the focused
  // number cycles its layout; the others focus their workspace.
  readonly property int slots: Math.max(1, Number(root.setting("slots", 5)))
  readonly property var layouts: ["dwindle", "master", "scrolling"]
  property string layout: "dwindle"

  // A wheel notch moves one workspace along the row; a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function workspaceIds() {
    const ids = []
    for (let i = 1; i <= root.slots; i++) ids.push(i)

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

  // Dispatched as Lua, for the same reason as DockHost: the config manager
  // rewrites `hyprctl dispatch workspace 3` into `hl.dispatch(workspace 3)`,
  // which is not a Lua expression. Verified against the running compositor.
  function focusWorkspace(id) {
    focusProc.command = ["hyprctl", "dispatch", "hl.dsp.focus({workspace = " + String(id) + "})"]
    focusProc.running = true
  }

  function refreshLayout() {
    layoutQuery.running = false
    layoutQuery.running = true
  }

  function cycleLayout() {
    if (root.focusedId < 1 || layoutSet.running) return

    const at = root.layouts.indexOf(root.layout)
    const next = root.layouts[(at + 1) % root.layouts.length]
    root.layout = next

    // A workspace rule is how Hyprland changes a layout at runtime; `hyprctl
    // keyword general:layout` would change every workspace instead.
    layoutSet.command = ["hyprctl", "eval",
      'hl.workspace_rule({ workspace = "' + root.focusedId + '", layout = "' + next + '" })']
    layoutSet.running = true
  }

  Component.onCompleted: root.refreshLayout()
  onFocusedIdChanged: if (layoutQuery) root.refreshLayout()

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

  Process {
    id: layoutQuery
    running: false
    command: ["hyprctl", "activeworkspace", "-j"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(String(this.text || "{}"))
          root.layout = String(data.tiledLayout || "dwindle")
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: layoutSet
    running: false

    // The write has landed when it stops running; read the layout back rather
    // than trusting the optimistic value if Hyprland rejected the name.
    onRunningChanged: if (!running) root.refreshLayout()
  }

  IpcHandler {
    target: "workspaces"

    function cycle(): void { root.cycleLayout() }
    function refresh(): void { root.refreshLayout() }
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
        // The active workspace is a brighter number, not a filled block: the
        // reference bar uses the block for hover and mode switches, not for the
        // workspace you are merely on.
        activeColor: Theme.accent
        selected: false
        dimmed: !button.focused && !root.occupied(button.modelData)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: Style.space(20)
        fixedHeight: Style.bar.sizeHorizontal
        tooltipText: button.focused
          ? "Workspace " + button.modelData + " · " + root.layout + " layout · click to cycle"
          : "Workspace " + button.modelData + " · click to focus"

        onPressed: function (button_) {
          if (button_ !== Qt.LeftButton) return
          if (button.focused) root.cycleLayout()
          else root.focusWorkspace(button.modelData)
        }
        onWheelMoved: function (delta) {
          root.scroll(delta)
        }
      }
    }
  }
}