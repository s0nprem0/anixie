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

  // `monitors workspaces sync` assigns each output a block of ten global
  // workspace ids: 1-10 on the first screen, 11-20 on the next, and so on. The
  // bar shows the local number (1-10) while Hyprland keeps the global id.
  readonly property string workspaceState: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/anixie/workspaces.json"
  property var mapping: ({})
  readonly property int base: {
    const value = Number(root.mapping[root.screenName])
    return isFinite(value) && value > 0 ? value : 1
  }

  property FileView mappingFile: FileView {
    path: Qt.resolvedUrl(root.workspaceState)
    printErrors: false
    blockLoading: true
    watchChanges: true

    Component.onCompleted: root.parseMapping()
    onTextChanged: root.parseMapping()
  }

  function parseMapping() {
    try {
      const data = JSON.parse(String(root.mappingFile.text() || "{}"))
      root.mapping = data && typeof data === "object" && !Array.isArray(data) ? data : ({})
    } catch (e) {
      root.mapping = ({})
    }
  }

  // A monitor event rewrites the mapping; reload rather than trusting a watch
  // that does not fire on every file in this shell.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name).indexOf("monitor") === 0) root.mappingFile.reload()
    }
  }

  // The first sync is started by Hyprland's own startup handler and can land
  // just after the bar reads the file. One reload shortly after boot picks it up
  // even when the file watch does not fire for a newly created path.
  property Timer mappingStartup: Timer {
    interval: 1500
    running: true
    repeat: false
    onTriggered: root.mappingFile.reload()
  }

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
  readonly property int slots: Math.max(1, Math.min(10, Number(root.setting("slots", 5))))
  readonly property var layouts: ["dwindle", "master", "scrolling"]
  property string layout: "dwindle"

  // A wheel notch moves one workspace along the row; a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function workspaceIds() {
    const ids = []
    for (let i = 0; i < root.slots; i++) ids.push(root.base + i)

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

  // One copy per bar, looked up by display for the IPC handler in shell.qml.
  Component.onCompleted: {
    WorkspacesHost.register(root)
    root.refreshLayout()
  }
  Component.onDestruction: WorkspacesHost.unregister(root)
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

  implicitWidth: root.vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: root.vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  Row {
    id: row
    anchors.centerIn: parent
    visible: !root.vertical
    spacing: Style.space(2)

    Repeater {
      model: root.workspaceIds()

      delegate: WidgetButton {
        id: button
        required property int modelData

        readonly property bool focused: root.focusedId === modelData
        readonly property int slot: button.modelData - root.base + 1

        text: button.slot === 10 ? "0" : String(button.slot > 0 ? button.slot : button.modelData)
        active: button.focused
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

  Column {
    id: column
    anchors.centerIn: parent
    visible: root.vertical
    spacing: Style.space(2)

    Repeater {
      model: root.workspaceIds()

      delegate: WidgetButton {
        id: vbutton
        required property int modelData

        readonly property bool focused: root.focusedId === modelData
        readonly property int slot: vbutton.modelData - root.base + 1

        text: vbutton.slot === 10 ? "0" : String(vbutton.slot > 0 ? vbutton.slot : vbutton.modelData)
        active: vbutton.focused
        activeColor: Theme.accent
        selected: false
        dimmed: !vbutton.focused && !root.occupied(vbutton.modelData)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: Style.bar.sizeVertical
        fixedHeight: Style.space(20)
        tooltipText: vbutton.focused
          ? "Workspace " + vbutton.modelData + " · " + root.layout + " layout · click to cycle"
          : "Workspace " + vbutton.modelData + " · click to focus"

        onPressed: function (button_) {
          if (button_ !== Qt.LeftButton) return
          if (vbutton.focused) root.cycleLayout()
          else root.focusWorkspace(vbutton.modelData)
        }
        onWheelMoved: function (delta) {
          root.scroll(delta)
        }
      }
    }
  }
}