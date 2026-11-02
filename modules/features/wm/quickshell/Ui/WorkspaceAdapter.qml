pragma Singleton

import QtQuick

// Compositor-agnostic workspace adapter used by the workspace overview.
//
// The overview binds to this object instead of Quickshell.Hyprland directly, so
// the same UI can run on Hyprland, Niri and (eventually) Mango. Each backend
// implements the same surface: `workspaces`, `focusedWorkspaceId`,
// `focusedAddress`, `refresh()`, `focusWorkspace()`, `focusWindow()`,
// `moveWindowToWorkspace()` and `closeWindow()`.
QtObject {
  id: root

  readonly property bool supported: CompositorHost.isHyprland || CompositorHost.isNiri

  readonly property var workspaces: {
    if (CompositorHost.isHyprland) return HyprlandWorkspaceAdapter.workspaces
    if (CompositorHost.isNiri) return NiriWorkspaceAdapter.workspaces
    return []
  }

  readonly property var focusedWorkspaceId: {
    if (CompositorHost.isHyprland) return HyprlandWorkspaceAdapter.focusedWorkspaceId
    if (CompositorHost.isNiri) return NiriWorkspaceAdapter.focusedWorkspaceId
    return null
  }

  readonly property string focusedAddress: {
    if (CompositorHost.isHyprland) return HyprlandWorkspaceAdapter.focusedAddress
    if (CompositorHost.isNiri) return NiriWorkspaceAdapter.focusedAddress
    return ""
  }

  function monitorNameOf(ws) {
    if (CompositorHost.isHyprland) return HyprlandWorkspaceAdapter.monitorNameOf(ws)
    if (CompositorHost.isNiri) return NiriWorkspaceAdapter.monitorNameOf(ws)
    if (CompositorHost.isMango) return MangoWorkspaceAdapter.monitorNameOf(ws)
    if (!ws) return ""
    if (typeof ws.monitor === "string") return ws.monitor
    if (ws.monitor && ws.monitor.name) return String(ws.monitor.name)
    if (ws.output) return String(ws.output)
    return ""
  }

  function findWindow(address) {
    if (CompositorHost.isHyprland) return HyprlandWorkspaceAdapter.findWindow(address)
    if (CompositorHost.isNiri) return NiriWorkspaceAdapter.findWindow(address)
    if (CompositorHost.isMango) return MangoWorkspaceAdapter.findWindow(address)
    return null
  }

  function refresh() {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.refresh()
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.refresh()
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.refresh()
  }

  function focusWorkspace(id) {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.focusWorkspace(id)
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.focusWorkspace(id)
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.focusWorkspace(id)
  }

  function focusWindow(address) {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.focusWindow(address)
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.focusWindow(address)
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.focusWindow(address)
  }

  function moveWindowToWorkspace(address, toId) {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.moveWindowToWorkspace(address, toId)
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.moveWindowToWorkspace(address, toId)
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.moveWindowToWorkspace(address, toId)
  }

  function moveWorkspaceToMonitor(workspaceId, monitor) {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.moveWorkspaceToMonitor(workspaceId, monitor)
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.moveWorkspaceToMonitor(workspaceId, monitor)
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.moveWorkspaceToMonitor(workspaceId, monitor)
  }

  function closeWindow(address) {
    if (CompositorHost.isHyprland) HyprlandWorkspaceAdapter.closeWindow(address)
    else if (CompositorHost.isNiri) NiriWorkspaceAdapter.closeWindow(address)
    else if (CompositorHost.isMango) MangoWorkspaceAdapter.closeWindow(address)
  }
}
