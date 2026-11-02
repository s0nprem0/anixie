pragma Singleton

import QtQuick

// Mango (mangowc) adapter. The compositor's IPC is not wired into this shell
// yet, so the workspace overview stays disabled there rather than calling into
// an interface that does not exist. The shape matches the other adapters so a
// future implementation can drop in without touching the overview.
QtObject {
  id: root

  readonly property bool supported: false
  property var workspaces: []
  property var focusedWorkspaceId: null
  property string focusedAddress: ""

  function monitorNameOf(ws) { return (ws && ws.monitor) ? String(ws.monitor) : "" }
  function findWindow(address) { return null }
  function refresh() {}
  function focusWorkspace(id) {}
  function focusWindow(address) {}
  function moveWindowToWorkspace(address, toId) {}
  function closeWindow(address) {}
  function moveWorkspaceToMonitor(workspaceId, monitor) {}

}
