pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

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
// That data still comes from `hyprctl`, but the timing comes from the module's
// event socket: `Hyprland.rawEvent` says when a window opened, closed, moved or
// took focus, and those are the moments the list is worth asking for again. The
// module's own state cannot be the trigger for the list — it is the list the
// module cannot provide — but its events are exactly right for saying when to
// fetch one.
QtObject {
  id: root

  property bool shown: false

  // A backstop between events, and only while the dock is on screen. Events
  // make it responsive; this is what covers the changes Hyprland does not
  // announce.
  readonly property int pollMs: 3000

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

  // Dispatched as Lua: the config manager rewrites `hyprctl dispatch focuswindow
  // address:0x..` into `hl.dispatch(focuswindow address:0x..)` before evaluating,
  // and that is not a Lua expression, so every call failed with "')' expected
  // near 'address'". Each form below was checked against the running compositor.
  function focus(address) {
    if (!address) return
    Commands.run("hyprctl dispatch 'hl.dsp.focus({window = \"" + address + "\"})'")
  }

  function focusActiveWorkspace(id) {
    Commands.run("hyprctl dispatch 'hl.dsp.focus({workspace = " + id + "})'")
  }

  // Close is dispatched by address rather than `activewindow`, so a click on the
  // wrong tile closes the tile's window and not whichever one happens to have
  // focus at that moment.
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
    if (!app || !app.windows || app.windows.length === 0) return
    const target = root.pickWindow(app.windows)
    if (!target) return

    // A minimized window has to come back to the current workspace before it is
    // worth focusing; focusing it where it is parked achieves nothing.
    if (target.minimized) {
      Commands.run("hyprctl dispatch 'hl.dsp.workspace.toggle_special({name = \"minimize\"})'")
    } else if (target.workspace !== root.activeWorkspace) {
      root.focusActiveWorkspace(target.workspace)
    }
    root.focus(target.address)
  }

  // ---- the poll ----

  property Process query: Process {
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

  // ---- refreshing ----
  //
  // The list is only wanted while the dock is on screen, and asking for it
  // unconditionally was the largest single thing this shell did at idle: two
  // processes a second, forever — `hyprctl clients -j` is a full JSON dump of
  // every window — for a dock that is hidden most of the time.

  // Which events change what the dock should show. Hyprland's event socket is
  // the trigger now rather than a clock: a window opening, closing, moving or
  // taking focus is exactly what changes the list, and those are the events it
  // emits.
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

  function refresh() {
    if (!root.shown) return

    if (!root.query.running) root.query.running = true
    // Where the pointer is matters for a dock: it is what decides which window
    // a click counts as hitting. Asked for alongside the list.
    if (!root.focusQuery.running) root.focusQuery.running = true
  }

  onShownChanged: if (root.shown) root.refresh()

  property Connections hyprlandEvents: Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (root.refreshOn[event.name]) root.refresh()
    }
  }

  // A backstop, not the mechanism. Some things that change the list do not emit
  // an event — the module's own docs say as much about toplevel state — and a
  // dock that is visibly wrong is worse than two processes every few seconds
  // while it is open.
  property Timer poll: Timer {
    interval: root.pollMs
    running: root.shown
    repeat: true
    onTriggered: root.refresh()
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

  // Nothing here: the dock is hidden at startup, and the first refresh is
  // `onShownChanged`'s job.
}