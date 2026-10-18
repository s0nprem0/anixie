pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The dock's state, and the three things a click can do to a window.
//
// The window list comes from `hyprctl clients -j` rather than from Quickshell's
// Hyprland module. The module is the tidier source — it is change-notifying, so
// it repaints the instant a window moves — but on this build its toplevels carry
// only address, title, activated, urgent, workspace and monitor. There is no
// class, so there is nothing to tell one Firefox window from another and no way
// to group them under an app or pick an icon for it. `hyprctl` reports class,
// initialClass, the workspace id, whether the window is mapped, where it is and
// how large it is, which is everything the dock needs.
//
// Polled rather than event-driven, which is the trade for that: a window
// opening or closing shows up within a second instead of immediately. Every
// other module here that has to read Hyprland's state does the same thing
// (Indicators polls hyprsunset and hypridle), so this is the established
// pattern rather than a new concession.
QtObject {
  id: root

  property bool shown: false

  // Long enough to feel immediate, short enough that a couple of processes an
  // hour is invisible next to everything else the shell runs.
  readonly property int pollMs: 1000

  property var clients: []

  function toggle() {
    root.shown = !root.shown
  }

  function show() {
    root.shown = true
  }

  function hide() {
    root.shown = false
  }

  // ---- reading ----

  function read(text) {
    const parsed = root.parse(text)
    // Only reassigned when something actually changed: `clients` is a var, so a
    // fresh array every second would re-run every binding in the dock and reset
    // whatever the pointer was hovering.
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

      // Hyprland keeps minimized windows in the client list with mapped false
      // rather than dropping them, which is what lets the dock bring one back.
      out.push({
        address: String(c.address),
        klass: String(c.class || c.initialClass || "app"),
        title: String(c.title || ""),
        workspace: c.workspace ? Number(c.workspace.id) : -1,
        mapped: c.mapped !== false,
        minimized: c.mapped === false,
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
      if (a[i].mapped !== b[i].mapped) return false
      if (a[i].workspace !== b[i].workspace) return false
      if (a[i].title !== b[i].title) return false
    }
    return true
  }

  // ---- what the dock draws ----

  // One tile per application, in the order the apps were first seen, each
  // carrying that app's windows. Grouping is the point: four Firefox windows are
  // four rows in the dock, not four launches of Firefox.
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

    return order.map(function (klass) { return byClass[klass] })
  }

  readonly property bool anyApps: root.apps.length > 0

  // The workspace the user is looking at, so a click can prefer a window that is
  // already in front of them. Read from the same poll rather than from the
  // Hyprland module, to keep one source for everything the dock believes.
  property int activeWorkspace: 1

  // Which window a click on an app brings forward.
  //
  // Windows on the workspace in front of the user come first, then minimized
  // ones — which come back to that workspace — and only then windows elsewhere,
  // since moving to another workspace to reach a window defeats the purpose.
  // Clicking an app whose best window is already focused moves on to the next
  // one, so repeated clicks cycle rather than appearing to do nothing.
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
        // The focused one is already up, so the click is asking for the next.
        return ordered[(i + 1) % ordered.length]
      }
    }
    return ordered[0]
  }

  // `hyprctl` reports no focused flag, so this compares against the window that
  // actually has input. Read back from the compositor rather than tracked here:
  // a window that closes under us leaves no event to clean up after.
  property var focusedAddress: ""

  function isFocused(address) {
    return root.focusedAddress === address
  }

  // ---- acting ----

  function focus(address) {
    if (!address) return
    Commands.run("hyprctl dispatch focuswindow address:" + Util.shellQuote(address))
  }

  function focusActiveWorkspace(id) {
    Commands.run("hyprctl dispatch workspace " + id)
  }

  // Close is dispatched by address rather than `activewindow`, so a click on the
  // wrong tile closes the tile's window and not whichever one happens to have
  // focus at that moment.
  function close(address) {
    if (!address) return
    Commands.run("hyprctl dispatch closewindow address:" + Util.shellQuote(address))
  }

  function minimize(address) {
    if (!address) return
    Commands.run("hyprctl dispatch togglespecialworkspace minimize")
    Commands.run("hyprctl dispatch focuswindow address:" + Util.shellQuote(address))
  }

  function activate(app) {
    if (!app || !app.windows || app.windows.length === 0) return
    const target = root.pickWindow(app.windows)
    if (!target) return

    // A minimized window has to come back to the current workspace before it is
    // worth focusing; focusing it where it is parked achieves nothing.
    if (target.minimized) {
      Commands.run("hyprctl dispatch togglespecialworkspace minimize")
    } else if (target.workspace !== root.activeWorkspace) {
      root.focusActiveWorkspace(target.workspace)
    }
    root.focus(target.address)
  }

  // ---- the poll ----

  property Process query: Process {
    running: true
    command: ["sh", "-c", "hyprctl clients -j; echo; hyprctl activeworkspace -j"]
    stdout: StdioCollector {
      onStreamFinished: root.onOutput(this.text)
    }
  }

  function onOutput(text) {
    // Two commands, so the split is on the blank line between them rather than
    // on a guess about how long the JSON is.
    const parts = String(text || "").split("\n")
    const split = parts.findIndex(function (line) { return line.trim() === "" })
    root.read(parts.slice(0, split === -1 ? parts.length : split).join("\n"))
    if (split !== -1) root.readActiveWorkspace(parts.slice(split + 1).join("\n"))
  }

  function readActiveWorkspace(text) {
    try {
      const parsed = JSON.parse(String(text || "").trim())
      if (parsed && typeof parsed.id === "number") root.activeWorkspace = parsed.id
    } catch (e) {
    }
  }

  // Held as a property rather than declared as a child: a QtObject has no default
  // property, so a bare `Timer { }` here has nowhere to go.
  property Timer poll: Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.query.running = true
      // Where the pointer is matters for a dock: it is what decides which window
      // a click counts as hitting. Asked for on the same tick as the list.
      root.focusQuery.running = true
    }
  }

  property Process focusQuery: Process {
    command: ["sh", "-c", "hyprctl activewindow -j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(this.text || "").trim())
          root.focusedAddress = parsed && parsed.address ? String(parsed.address) : ""
        } catch (e) {
          root.focusedAddress = ""
        }
      }
    }
  }

  Component.onCompleted: root.query.running = true
}