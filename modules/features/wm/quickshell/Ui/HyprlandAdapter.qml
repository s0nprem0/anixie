pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland-specific window/workspace adapter.
//
// The dock used to own this logic directly. Moving it here puts the compositor
// specifics behind one object: the dock (and, later, the workspace overview)
// binds to `clients` and `activeWorkspace` without knowing how they are read.
// Niri and Mango adapters will implement the same surface.
QtObject {
  id: root

  // Whether the consumer (the dock) is on screen. The query only runs while it
  // is, so a hidden dock costs nothing at idle.
  property bool enabled: false

  property var clients: []

  readonly property int activeWorkspace: Hyprland.focusedWorkspace
    ? Number(Hyprland.focusedWorkspace.id)
    : 1

  readonly property string focusedAddress: {
    for (let i = 0; i < root.clients.length; i++) {
      if (root.clients[i].focused) return root.clients[i].address
    }
    return ""
  }

  function toggle() {}
  function show() {}
  function hide() {}

  // ---- reading ----

  function read(text) {
    const parsed = root.parse(text)
    if (root.sameClients(parsed, root.clients)) return
    root.clients = parsed
  }

  function parse(text) {
    const out = []
    let parsed
    try {
      parsed = JSON.parse(String(text || ""))
    } catch (e) {
      return out
    }
    if (!Array.isArray(parsed)) return out

    for (let i = 0; i < parsed.length; i++) {
      const c = parsed[i]
      if (!c || !c.address) continue

      out.push({
        address: String(c.address),
        klass: String(c.class || c.initialClass || "app"),
        title: String(c.title || ""),
        workspace: c.workspace ? Number(c.workspace.id) : -1,
        mapped: c.mapped !== false,
        minimized: c.mapped === false,
        focused: Number(c.focusHistoryID) === 0,
        fullscreen: Number(c.fullscreen || 0) > 0,
        at: Array.isArray(c.at) ? c.at : [0, 0],
        size: Array.isArray(c.size) ? c.size : [0, 0]
      })
    }
    return out
  }

  function sameClients(a, b) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) {
      if (a[i].address !== b[i].address) return false
      if (a[i].focused !== b[i].focused) return false
      if (a[i].mapped !== b[i].mapped) return false
      if (a[i].workspace !== b[i].workspace) return false
      if (a[i].title !== b[i].title) return false
    }
    return true
  }

  function refresh() {
    if (!root.enabled) return
    if (!root.query.running) root.query.running = true
  }

  onEnabledChanged: if (root.enabled) root.refresh()

  property Process query: Process {
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.read(this.text)
    }
  }

  readonly property var refreshOn: ({
    openwindow: true,
    closewindow: true,
    movewindow: true,
    activewindow: true,
    workspace: true,
    moveworkspace: true,
    fullscreen: true,
    changefloatingmode: true,
    urgent: true,
    minimize: true,
    windowtitle: true
  })

  property Connections hyprlandEvents: Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (root.enabled && root.refreshOn[event.name]) root.refresh()
    }
  }

  property Timer poll: Timer {
    interval: 3000
    running: root.enabled
    repeat: true
    onTriggered: root.refresh()
  }
}
