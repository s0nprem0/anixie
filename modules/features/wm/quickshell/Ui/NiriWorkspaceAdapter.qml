pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Niri implementation of the workspace adapter. Niri has no in-process QML
// module here, so the data comes from `niri msg -j` and is polled while the
// shell is running. The shapes mirror the Hyprland adapter's so the overview
// can stay compositor-agnostic.
QtObject {
  id: root

  property var workspaces: []
  property var rawWorkspaces: []
  property var rawWindows: []

  property var focusedWorkspaceId: null
  property string focusedAddress: ""

  property Timer poll: Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  function monitorNameOf(ws) {
    if (!ws) return ""
    if (typeof ws.monitor === "string") return ws.monitor
    if (ws.monitor && ws.monitor.name) return String(ws.monitor.name)
    if (ws.output) return String(ws.output)
    return ""
  }

  function findWindow(address) {
    for (let i = 0; i < (root.rawWindows || []).length; i++) {
      const w = root.rawWindows[i]
      if (w && String(w.id) === String(address)) {
        return { address: String(w.id), workspace: w.workspace_id }
      }
    }
    return null
  }

  function parseWorkspaces(text) {
    try {
      const arr = JSON.parse(String(text || "[]"))
      root.rawWorkspaces = Array.isArray(arr) ? arr : []
    } catch (e) {
      root.rawWorkspaces = []
    }
  }

  function parseWindows(text) {
    try {
      const arr = JSON.parse(String(text || "[]"))
      root.rawWindows = Array.isArray(arr) ? arr : []
    } catch (e) {
      root.rawWindows = []
    }
  }

  function rebuild() {
    const wsMap = {}
    const result = []
    for (let i = 0; i < root.rawWorkspaces.length; i++) {
      const w = root.rawWorkspaces[i] || {}
      const ws = {
        id: w.id,
        name: String(w.name || ""),
        monitor: String(w.output || ""),
        active: w.is_active === true,
        focused: w.is_focused === true,
        toplevels: { values: [] }
      }
      wsMap[w.id] = ws
      result.push(ws)
    }
    for (let i = 0; i < root.rawWindows.length; i++) {
      const win = root.rawWindows[i] || {}
      const ws = wsMap[win.workspace_id]
      if (!ws) continue
      const size = (win.layout && Array.isArray(win.layout.window_size)) ? win.layout.window_size : [0, 0]
      ws.toplevels.values.push({
        address: String(win.id),
        title: String(win.title || ""),
        class: String(win.app_id || ""),
        appId: String(win.app_id || ""),
        focused: win.is_focused === true,
        at: [0, 0],
        size: size
      })
    }
    root.workspaces = result

    let focusedWs = null
    for (let i = 0; i < root.rawWorkspaces.length; i++) {
      if (root.rawWorkspaces[i] && root.rawWorkspaces[i].is_focused) { focusedWs = root.rawWorkspaces[i].id; break }
    }
    root.focusedWorkspaceId = focusedWs

    let focusedWin = ""
    for (let i = 0; i < root.rawWindows.length; i++) {
      if (root.rawWindows[i] && root.rawWindows[i].is_focused) { focusedWin = String(root.rawWindows[i].id); break }
    }
    root.focusedAddress = focusedWin
  }

  function refresh() {
    if (workspaceProc.running || windowProc.running) return
    workspaceProc.running = true
  }

  property Process workspaceProc: Process {
    command: ["niri", "msg", "-j", "workspaces"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.parseWorkspaces(this.text)
        if (!root.windowProc.running) root.windowProc.running = true
      }
    }
  }

  property Process windowProc: Process {
    command: ["niri", "msg", "-j", "windows"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.parseWindows(this.text)
        root.rebuild()
      }
    }
  }

  function focusWorkspace(id) {
    if (id === undefined || id === null) return
    const ws = String(id)
    try { Commands.run(["niri", "msg", "action", "focus-workspace-id", ws]); return } catch (e) {}
    try { Commands.run(["niri", "msg", "action", "focus-workspace", ws]) } catch (e) {}
  }

  function focusWindow(address) {
    if (!address) return
    const addr = String(address).replace(/^address:/, "")
    try { Commands.run(["niri", "msg", "action", "focus-window", "--id", addr]); return } catch (e) {}
    try { Commands.run("niri msg action focus-window --id " + addr) } catch (e) {}
  }

  function moveWindowToWorkspace(address, toId) {
    if (!address || toId === undefined || toId === null) return
    const addr = String(address).replace(/^address:/, "")
    const ws = String(toId)
    try { Commands.run(["niri", "msg", "action", "move-window-to-workspace-id", "--window-id", addr, ws]); return } catch (e) {}
    try { Commands.run(["niri", "msg", "action", "move-window-to-workspace", "--window-id", addr, ws]) } catch (e) {}
  }

  function moveWorkspaceToMonitor(workspaceId, monitor) {
    if (workspaceId === undefined || workspaceId === null || !monitor) return
    const ws = String(workspaceId)
    const mon = String(monitor)
    try { Commands.run(["niri", "msg", "action", "move-workspace-to-monitor", "--workspace-id", ws, mon]); return } catch (e) {}
    try { Commands.run(["niri", "msg", "action", "move-workspace-to-monitor", mon]) } catch (e) {}
  }

  function closeWindow(address) {
    if (!address) return
    const addr = String(address).replace(/^address:/, "")
    try { Commands.run(["niri", "msg", "action", "close-window", "--id", addr]); return } catch (e) {}
    try { Commands.run("niri msg action close-window --id " + addr) } catch (e) {}
  }
}
