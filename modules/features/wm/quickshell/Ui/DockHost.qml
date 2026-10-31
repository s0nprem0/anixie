pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The dock's state, and the three things a click can do to a window.
//
// Window data now comes from HyprlandAdapter, which owns the compositor-
// specific reading. This host keeps the dock's own state (shown, auto-hide,
// pinned apps) and the actions that act on windows.
QtObject {
  id: root

  property bool shown: false

  // Auto-hide the dock when the active workspace has no windows. Off by
  // default: the dock is otherwise a manual toggle, and hiding it
  // automatically would surprise anyone who opened it on purpose.
  property bool autoHide: false

  // Running indicator style for tiles that have a window open.
  property string indicatorStyle: "dot"

  // Pinned apps stay in the dock even with no window. Persisted separately
  // from the bar layout so a dock reset does not touch the bar.
  property var pinned: []

  function isPinned(klass) {
    return root.pinned.indexOf(String(klass || "")) !== -1
  }

  function pin(klass) {
    klass = String(klass || "")
    if (klass === "" || root.isPinned(klass)) return
    const next = root.pinned.slice()
    next.push(klass)
    root.pinned = next
    root.saveDock()
  }

  function unpin(klass) {
    klass = String(klass || "")
    const next = root.pinned.filter(function (k) { return k !== klass })
    if (next.length === root.pinned.length) return
    root.pinned = next
    root.saveDock()
  }

  function saveDock() {
    try { root.dockFile.setText(JSON.stringify({ pinned: root.pinned }, null, 2) + "\n") } catch (e) {}
  }

  function loadDock() {
    try {
      const raw = root.dockFile.text()
      const parsed = JSON.parse(raw || "{}")
      if (parsed && Array.isArray(parsed.pinned)) root.pinned = parsed.pinned.map(String)
    } catch (e) {}
  }

  property FileView dockFile: FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/anixie/dock.json"
    printErrors: false
    blockLoading: true
    Component.onCompleted: root.loadDock()
  }

  // Data and focus come from the adapter.
  readonly property var clients: HyprlandAdapter.clients
  readonly property int activeWorkspace: HyprlandAdapter.activeWorkspace
  readonly property string focusedAddress: HyprlandAdapter.focusedAddress

  readonly property var apps: {
    const byClass = {}
    const order = []

    for (let i = 0; i < root.clients.length; i++) {
      const c = root.clients[i]
      if (!byClass[c.klass]) {
        byClass[c.klass] = { klass: c.klass, windows: [] }
        order.push(c.klass)
      }
      byClass[c.klass].windows.push(c)
    }

    const result = []
    const seen = {}
    for (let i = 0; i < root.pinned.length; i++) {
      const klass = String(root.pinned[i])
      if (klass === "" || seen[klass]) continue
      seen[klass] = true
      const entry = byClass[klass]
      result.push(entry ? entry : { klass: klass, windows: [] })
    }
    for (let i = 0; i < order.length; i++) {
      const klass = order[i]
      if (seen[klass]) continue
      seen[klass] = true
      result.push(byClass[klass])
    }
    return result
  }

  readonly property bool anyApps: root.apps.length > 0

  function isFocused(address) {
    return root.focusedAddress === address
  }

  // ---- actions ----

  function toggle() { root.shown = !root.shown }
  function show() { root.shown = true }
  function hide() { root.shown = false }

  function focus(address) {
    if (!address) return
    Commands.run("hyprctl dispatch 'hl.dsp.focus({window = \"" + address + "\"})'")
  }

  function focusActiveWorkspace(id) {
    Commands.run("hyprctl dispatch 'hl.dsp.focus({workspace = " + id + "})'")
  }

  function close(address) {
    if (!address) return
    Commands.run("hyprctl dispatch 'hl.dsp.window.close({address = \"" + address + "\"})'")
  }

  function minimize(address) {
    if (!address) return
    Commands.run("hyprctl dispatch 'hl.dsp.workspace.toggle_special({name = \"minimize\"})'")
    Commands.run("hyprctl dispatch 'hl.dsp.focus({window = \"" + address + "\"})'")
  }

  function activate(app) {
    if (!app || !app.windows || app.windows.length === 0) {
      if (app && app.klass) Commands.app(app.klass)
      return
    }
    const target = root.pickWindow(app.windows)
    if (!target) return

    if (target.minimized) {
      Commands.run("hyprctl dispatch 'hl.dsp.workspace.toggle_special({name = \"minimize\"})'")
    } else if (target.workspace !== root.activeWorkspace) {
      root.focusActiveWorkspace(target.workspace)
    }
    root.focus(target.address)
  }

  function pickWindow(windows) {
    const list = windows || []
    if (list.length === 0) return null
    if (list.length === 1) return list[0]

    const rank = function (w) {
      if (w.minimized) return 1
      return w.workspace === root.activeWorkspace ? 0 : 2
    }

    const ordered = list.slice().sort(function (a, b) { return rank(a) - rank(b) })

    for (let i = 0; i < ordered.length; i++) {
      if (root.isFocused(ordered[i].address)) {
        return ordered[(i + 1) % ordered.length]
      }
    }
    return ordered[0]
  }

  // ---- auto-hide ----

  property bool hasWindowsOnActiveWorkspace: {
    for (let i = 0; i < root.clients.length; i++) {
      const c = root.clients[i]
      if (c.mapped && c.workspace === root.activeWorkspace) return true
    }
    return false
  }

  property Timer autoHideTimer: Timer {
    interval: 1500
    running: root.autoHide && root.shown && !root.hasWindowsOnActiveWorkspace
    repeat: false
    onTriggered: root.shown = false
  }

  onShownChanged: {
    HyprlandAdapter.enabled = root.shown
    if (root.shown) HyprlandAdapter.refresh()
  }
  onHasWindowsOnActiveWorkspaceChanged: if (root.autoHide && root.shown && !root.hasWindowsOnActiveWorkspace) root.autoHideTimer.restart()
}
