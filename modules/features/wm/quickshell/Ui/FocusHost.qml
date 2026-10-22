pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Focus mode: a timer that closes the configured distractions and silences
// notifications while it runs.
//
// The shell is the right owner for this rather than a separate daemon: it
// already watches every toplevel for the dock and the active-window widget, and
// it already owns the notification daemon, so silencing is a property change
// rather than an IPC dance between two processes. The state is written to disk
// so a shell restart — which an update performs — does not quietly end a focus
// block.
QtObject {
  id: root

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie"
  readonly property string statePath: root.stateDir + "/focus.json"

  // Updated by the timer rather than read directly in the bindings: Date.now()
  // is not observable, and a binding on it would only ever see the value at the
  // moment it was first evaluated.
  property double now: Date.now()
  property double until: 0
  property double started: 0
  property bool priorDnd: false
  property bool ready: false

  // Filled from focus.json, which quickshell/default.nix renders from the Nix
  // options. The fallbacks are what a shell recovering from a broken config
  // uses; they are deliberately the same list the module ships.
  property var blocked: [
    "discord", "equicord", "vesktop", "telegram", "steam", "lutris", "heroic"
  ]
  property int defaultMinutes: 25

  readonly property bool active: root.until > root.now
  readonly property int remainingSeconds: root.active
    ? Math.max(0, Math.ceil((root.until - root.now) / 1000))
    : 0
  readonly property string remainingLabel: root.formatDuration(root.remainingSeconds)

  function formatDuration(seconds) {
    const total = Math.max(0, Math.round(seconds))
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return total + "s"
  }

  function applyConfig(text) {
    try {
      const config = JSON.parse(String(text || ""))
      if (config && Array.isArray(config.blocked)) root.blocked = config.blocked
      if (config && Number(config.defaultMinutes) > 0) root.defaultMinutes = Number(config.defaultMinutes)
    } catch (e) {
      // A missing or malformed focus.json is not a reason to stop working: the
      // fallback list above is the same one the module ships.
    }
    root.ready = true
  }

  function restore(text) {
    try {
      const state = JSON.parse(String(text || ""))
      if (!state || Number(state.until) <= Date.now()) {
        // A block that ran out while the shell was down still has to put the
        // notification setting back; otherwise the next session silently starts
        // with notifications off.
        root.until = 0
        if (state && Number(state.until) > 0) {
          root.priorDnd = !!state.priorDnd
          root.applyDnd(root.priorDnd)
          root.pushIndicator()
        }
        return
      }
      root.until = Number(state.until)
      root.started = Number(state.started) || 0
      root.priorDnd = !!state.priorDnd
      root.now = Date.now()
      root.applyDnd(true)
      root.pushIndicator()
      root.enforce()
    } catch (e) {
      root.until = 0
    }
  }

  function isBlocked(appId) {
    const id = String(appId || "").toLowerCase()
    if (id === "") return false
    for (let i = 0; i < root.blocked.length; i++) {
      const pattern = String(root.blocked[i] || "").toLowerCase()
      if (pattern !== "" && id.indexOf(pattern) !== -1) return true
    }
    return false
  }

  function enforce() {
    if (!root.active) return

    const toplevels = ToplevelManager.toplevels.values || []
    for (let i = 0; i < toplevels.length; i++) {
      const toplevel = toplevels[i]
      if (!toplevel || !root.isBlocked(toplevel.appId)) continue
      try {
        toplevel.close()
      } catch (e) {
        // A client can vanish between the list read and the close. There is
        // nothing useful to do about that one.
      }
    }
  }

  function applyDnd(value) {
    NotificationHost.setDnd(!!value)
  }

  function pushIndicator() {
    IndicatorHost.setFocus(root.active)
  }

  function persist() {
    root.pendingWrite = JSON.stringify({
      until: root.until,
      started: root.started,
      priorDnd: root.priorDnd
    })
    root.mkdir.running = false
    root.mkdir.running = true
  }

  function start(minutes) {
    let duration = parseInt(minutes, 10)
    if (!isFinite(duration) || duration <= 0) duration = root.defaultMinutes
    duration = Math.min(480, duration)

    if (!root.active) root.priorDnd = NotificationHost.doNotDisturb
    root.now = Date.now()
    if (!root.active) root.started = root.now
    root.until = root.now + duration * 60000

    root.applyDnd(true)
    root.pushIndicator()
    root.persist()
    root.enforce()
    return root.status()
  }

  function extend(minutes) {
    if (!root.active) return root.start(minutes)

    let duration = parseInt(minutes, 10)
    if (!isFinite(duration) || duration <= 0) duration = root.defaultMinutes
    root.now = Date.now()
    root.until += Math.min(480, duration) * 60000
    root.persist()
    return root.status()
  }

  function stop() {
    const wasActive = root.until > 0
    if (wasActive) root.applyDnd(root.priorDnd)
    root.until = 0
    root.started = 0
    root.pushIndicator()
    root.persist()
    return "off"
  }

  function status() {
    return root.active ? "on " + root.remainingLabel : "off"
  }

  property string pendingWrite: ""

  property Process mkdir: Process {
    command: ["mkdir", "-p", root.stateDir]
    running: false

    onExited: {
      if (root.pendingWrite === "") return
      root.stateFile.setText(root.pendingWrite)
      root.pendingWrite = ""
    }
  }

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
    atomicWrites: true
    onLoaded: root.restore(this.text())
  }

  property FileView configFile: FileView {
    path: Qt.resolvedUrl("../focus.json")
    printErrors: false
    blockLoading: true
    onLoaded: root.applyConfig(this.text())
  }

  property Timer clock: Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      root.now = Date.now()
      if (root.until > 0 && root.until <= root.now) {
        root.stop()
        return
      }
      if (root.active) {
        // Re-assert both halves: a blocked app can open again between ticks, and
        // DND can be switched off from the indicator while a block is running.
        root.applyDnd(true)
        root.enforce()
      }
    }
  }

  Component.onCompleted: root.pushIndicator()
}
