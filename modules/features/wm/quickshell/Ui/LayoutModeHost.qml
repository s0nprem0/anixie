pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The global tiling/floating switch, as the shell sees it.
//
// The Hyprland plugin owns the mode: it is the only thing that can rebuild the
// scrolling tape without animating through it. It records the mode in a small
// state file, and that file is the interface used here — watching it means a
// toggle from the key, the bar module, or a plain `hyprctl layoutmode toggle`
// reaches the shell without polling.
//
// The first read is the mode inherited at login, not a change, so it does not
// open an OSD. The plugin writes the file at startup as well as on every
// toggle, so the watch has something to hold from the first compositor frame.
QtObject {
  id: root

  property bool floating: false

  // Set by the first successful read. Until then a value is the state the
  // session started in, and announcing it would be a toast nobody asked for.
  property bool known: false

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/hypr/layoutmode"

  function apply(text, announce) {
    const mode = String(text || "").trim()
    if (mode !== "floating" && mode !== "tiling") return

    const next = mode === "floating"
    const changed = root.known && next !== root.floating

    root.floating = next
    root.known = true

    if (changed && announce) root.announce()
  }

  function announce() {
    OsdHost.show(
      root.floating ? "layout-floating" : "layout-tiling",
      root.floating ? "Floating layout" : "Tiling layout"
    )
  }

  // Ask the plugin, then read the result back rather than flipping the cached
  // value optimistically: a toggle can fail (no eligible windows, an internal
  // error), and the bar should agree with the compositor afterwards.
  function toggle() {
    if (root.toggleProcess.running) return
    root.toggleProcess.running = true
  }

  property Process toggleProcess: Process {
    command: ["hyprctl", "layoutmode", "toggle"]
    onRunningChanged: if (!running) root.file.reload()
  }

  property FileView file: FileView {
    path: root.statePath
    printErrors: false
    watchChanges: true

    Component.onCompleted: root.apply(root.file.text(), false)
    onFileChanged: root.file.reload()
    onLoaded: root.apply(root.file.text(), root.known)
    onTextChanged: root.apply(root.file.text(), root.known)
  }

  // The state directory is created by the plugin, and the shell service can
  // start before that path exists on a fresh home. A watcher cannot be added to
  // a directory that is not there, so one read shortly after startup puts the
  // file (and its watch) in place even when the first attempt missed it.
  property Timer startupRead: Timer {
    interval: 1500
    running: true
    repeat: false
    onTriggered: root.file.reload()
  }
}
