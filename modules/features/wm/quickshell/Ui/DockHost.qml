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
// how large it is, which is everything the dock needs. It also reports
// `focusHistoryID`, 0 on the focused window, so the dump carries what used to be
// a second `hyprctl activewindow` call.
//
// That data still comes from `hyprctl`, but the timing comes from the module's
// event socket: `Hyprland.rawEvent` says when a window opened, closed, moved or
// took focus, and those are the moments the list is worth asking for again. The
// focused workspace is the one thing taken from the module directly, since it
// has it and is event-driven even when the client list would not change — on an
// empty workspace, for instance.
QtObject {
  id: root

  property bool shown: false

  // Auto-hide the dock when the active workspace has no windows. Off by
  // default: the dock is otherwise a manual toggle, and hiding it
  // automatically would surprise anyone who opened it on purpose.
  property bool autoHide: false

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

    // Pinned apps that are not currently running still get a tile, so they
    // can be launched from the dock. They carry an empty window list.
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

  readonly property bool hasWindowsOnActiveWorkspace: {
    for (let i = 0; i < root.clients.length; i++) {
      const c = root.clients[i]
      if (c.mapped && c.workspace === root.activeWorkspace) return true
    }
    return false
  }

  // The workspace the user is looking at, so a click can prefer a window that is
  // already in front of them.
  readonly property int activeWorkspace: Hyprland.focusedWorkspace
    ? Number(Hyprland.focusedWorkspace.id)
    : 1

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

  // `focusHistoryID` is 0 on the window that actually has input. Read from the
  // same dump rather than tracked here: a window that closes under us leaves no
  // event to clean up after.
  readonly property string focusedAddress: {
    for (let i = 0; i < root.clients.length; i++) {
      if (root.clients[i].focused) return root.clients[i].address
    }
    return ""
  }

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
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.read(this.text)
    }
  }

  // ---- refreshing ----
  //
  // The list is only wanted while the dock is on screen, and asking for it
  // unconditionally was the largest single thing this shell did at idle: a shell
  // and two `hyprctl`s a second, forever — `hyprctl clients -j` is a full JSON
  // dump of every window — for a dock that is hidden most of the time. It is one
  // process now, and only while the dock is open.

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
  }

  onShownChanged: if (root.shown) root.refresh()
  onHasWindowsOnActiveWorkspaceChanged: if (root.autoHide && root.shown && !root.hasWindowsOnActiveWorkspace) root.autoHideTimer.restart()

  property Connections hyprlandEvents: Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (root.refreshOn[event.name]) root.refresh()
    }
  }

  // A backstop, not the mechanism. Some things that change the list do not emit
  // an event — the module's own docs say as much about toplevel state — and a
  // dock that is visibly wrong is worse than one process every few seconds
  // while it is open.
  property Timer poll: Timer {
    interval: root.pollMs
    running: root.shown
    repeat: true
    onTriggered: root.refresh()
  }

  // Auto-hide: when enabled and the dock is open on an empty workspace, hide
  // it after a short delay so a glance does not flicker it away. The dock window
  // stays mapped (see the bar's rule) and the keybind can bring it back.
  property Timer autoHideTimer: Timer {
    interval: 1500
    running: root.autoHide && root.shown && !root.hasWindowsOnActiveWorkspace
    repeat: false
    onTriggered: root.shown = false
  }

  // Nothing here: the dock is hidden at startup, and the first refresh is
  // `onShownChanged`'s job.
}
