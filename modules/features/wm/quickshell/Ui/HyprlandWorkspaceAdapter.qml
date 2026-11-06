pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Hyprland implementation of the workspace adapter used by the workspace
// overview. It mostly proxies Quickshell.Hyprland for the reactive
// workspace/toplevel lists and HyprlandAdapter for client data, and turns
// the overview's actions into hyprctl dispatches.
QtObject {
  id: root

  readonly property var workspaces: Hyprland.workspaces ? (Hyprland.workspaces.values || []) : []

  readonly property var focusedWorkspaceId: Hyprland.focusedWorkspace
    ? (isNaN(Number(Hyprland.focusedWorkspace.id)) ? Hyprland.focusedWorkspace.id : Number(Hyprland.focusedWorkspace.id))
    : null

  readonly property string focusedAddress: HyprlandAdapter.focusedAddress

  readonly property var clients: HyprlandAdapter.clients

  function monitorNameOf(ws) {
    if (!ws) return ""
    if (typeof ws.monitor === "string") return ws.monitor
    if (ws.monitor && ws.monitor.name) return String(ws.monitor.name)
    if (ws.monitorName) return String(ws.monitorName)
    if (ws.output) return String(ws.output)
    return ""
  }

  function findWindow(address) {
    const clients = HyprlandAdapter.clients || []
    for (let i = 0; i < clients.length; i++) {
      if (clients[i] && String(clients[i].address) === String(address)) return clients[i]
    }
    // Fall back to scanning the toplevels if the adapter is disabled.
    const workspaces = root.workspaces || []
    for (let i = 0; i < workspaces.length; i++) {
      const toplevels = workspaces[i] && workspaces[i].toplevels ? (workspaces[i].toplevels.values || []) : []
      for (let j = 0; j < toplevels.length; j++) {
        if (toplevels[j] && String(toplevels[j].address) === String(address)) {
          return { address: String(toplevels[j].address), workspace: workspaces[i].id }
        }
      }
    }
    return null
  }

  function refresh() {
    try { HyprlandAdapter.refresh() } catch (e) {}
  }

  function focusWorkspace(id) {
    if (id === undefined || id === null) return
    const ws = String(id)
    try { Commands.run("hyprctl dispatch 'hl.dsp.focus({workspace = " + ws + "})'"); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "workspace", ws]); return } catch (e) {}
    try { Commands.run("hyprctl dispatch workspace " + ws) } catch (e) {}
  }

  function focusWindow(address) {
    if (!address) return
    const addr = String(address).replace(/^address:/, "")
    try { Commands.run("hyprctl dispatch 'hl.dsp.focus({window = \"address:" + addr + "\"})'"); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "focuswindow", "address:" + addr]); return } catch (e) {}
    try { Commands.run("hyprctl dispatch focuswindow address:" + addr) } catch (e) {}
  }

  function moveWindowToWorkspace(address, toId) {
    if (!address || toId === undefined || toId === null) return
    const addr = String(address).replace(/^address:/, "")
    const ws = String(toId)
    try { Commands.run("hyprctl dispatch 'hl.dsp.window.move({window = \"address:" + addr + "\", workspace = " + ws + "})'"); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "movetoworkspacesilent", ws + ",address:" + addr]); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "movetoworkspace", ws + ",address:" + addr]); return } catch (e) {}
    try { Commands.run("hyprctl dispatch movetoworkspace " + ws + ",address:" + addr) } catch (e) {}
  }

  function moveWorkspaceToMonitor(workspaceId, monitor) {
    if (workspaceId === undefined || workspaceId === null || !monitor) return
    const ws = String(workspaceId)
    const mon = String(monitor)
    try { Commands.run("hyprctl dispatch moveworkspacetomonitor " + ws + " " + mon); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "moveworkspacetomonitor", ws, mon]) } catch (e) {}
  }

  function closeWindow(address) {
    if (!address) return
    const addr = String(address).replace(/^address:/, "")
    try { Commands.run("hyprctl dispatch 'hl.dsp.window.close({address = \"address:" + addr + "\"})'"); return } catch (e) {}
    try { Commands.run(["hyprctl", "dispatch", "closewindow", "address:" + addr]) } catch (e) {}
  }
}
