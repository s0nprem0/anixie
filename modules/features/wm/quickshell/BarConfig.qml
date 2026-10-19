pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The bar's layout: which module sits in which section, and in what order.
//
// It used to be a read-only store symlink, which is fine for a file you edit and
// rebuild but useless for one the bar itself moves things around in — a drag has
// nowhere to persist. So there are two files: the built-in one bar.json that
// ships with the config, and a saved layout under the state directory. The saved
// one wins when it exists; deleting it puts the shipped layout back.
//
// Kept as plain JSON rather than a Nix expression for the same reason the theme
// is: the shell has to read and write it.
QtObject {
  id: root

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/anixie/bar"
  readonly property string savedPath: root.stateDir + "/bar.json"

  // Stand-in for a missing or broken bar.json, so a typo in the config never
  // leaves the session without a bar at all.
  readonly property var fallback: ({
    background: "clear",
    layout: {
      left: [{ id: "bar.workspaces" }],
      centerBegin: [],
      center: [{ id: "bar.clock" }],
      centerEnd: [],
      right: [
        { id: "bar.active-window" },
        { id: "bar.microphone" },
        { id: "bar.wifi" },
        { id: "bar.audio" },
        { id: "bar.power" }
      ]
    }
  })

  // The shipped file, and whatever the bar has saved over it. Both are read once
  // (and the saved one watched) — the shipped file is a store path that cannot
  // change without a rebuild, which restarts the shell anyway.
  property var builtin: root.fallback
  property string saved: ""

  readonly property var config: {
    if (root.saved !== "") {
      try {
        const parsed = JSON.parse(root.saved)
        if (parsed && typeof parsed === "object") return parsed
      } catch (e) {
        console.warn("quickshell bar: the saved layout is not valid JSON, using bar.json")
      }
    }
    return root.builtin
  }

  readonly property var layout: root.config.layout ? root.config.layout : {}

  // The layout entries of a section. The bar.json section names are the ones the
  // bar already uses: left, centerBegin, center, centerEnd, right.
  function section(name) {
    const entries = root.layout[name]
    return entries && entries.length ? entries : []
  }

  function reloadBuiltin() {
    let raw = ""
    try {
      raw = root.builtinFile.text()
    } catch (e) {
      raw = ""
    }
    if (!raw || raw.trim() === "") return

    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") root.builtin = parsed
      else console.warn("quickshell bar: bar.json is not an object, keeping the previous config")
    } catch (e) {
      console.warn("quickshell bar: bar.json is not valid JSON, keeping the previous config")
    }
  }

  function reloadSaved() {
    try {
      root.saved = root.savedFile.text()
    } catch (e) {
      root.saved = ""
    }
  }

  // Where a module should go, given a section name and an index in that section's
  // array. The dirty part is the index: the caller computes it with the module
  // still in place, so moving something later within its own section has to shift
  // by one — otherwise dragging a widget one place to the right lands it back
  // where it started.
  function move(id, toSection, index) {
    if (!id || !toSection) return

    const next = JSON.parse(JSON.stringify(root.config))
    next.layout = next.layout || {}

    let fromSection = ""
    let fromIndex = -1
    let entry = null

    for (const name in next.layout) {
      const list = next.layout[name]
      for (let i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === id) {
          fromSection = name
          fromIndex = i
          entry = list[i]
          list.splice(i, 1)
          break
        }
      }
      if (entry) break
    }

    if (!entry) return
    if (!next.layout[toSection]) next.layout[toSection] = []

    const target = next.layout[toSection]
    let at = Number(index)
    if (!isFinite(at) || at < 0) at = target.length
    if (fromSection === toSection && fromIndex >= 0 && fromIndex < at) at -= 1
    at = Math.max(0, Math.min(target.length, at))
    target.splice(at, 0, entry)

    root.save(next)
  }

  function save(next) {
    // The directory is made first and synchronously enough to matter: a write
    // into a directory that does not exist yet is a drop that silently does
    // nothing.
    root.pending = next
    mkdir.running = false
    mkdir.running = true
  }

  // Put the shipped layout back, by taking the saved one away.
  function reset() {
    root.saved = ""
    rm.running = false
    rm.running = true
  }

  property var pending: null

  property Process mkdir: Process {
    command: ["mkdir", "-p", root.stateDir]
    running: false
    onExited: {
      if (!root.pending) return
      root.savedFile.setText(JSON.stringify(root.pending, null, 2) + "\n")
      root.pending = null
    }
  }

  property Process rm: Process {
    command: ["rm", "-f", root.savedPath]
    running: false
    onExited: root.saved = ""
  }

  // A FileView held as a property rather than a child: a QtObject has no
  // default property, so a bare child declaration would never attach.
  property FileView builtinFile: FileView {
    path: Qt.resolvedUrl("bar.json")
    printErrors: false
    blockLoading: true

    Component.onCompleted: root.reloadBuiltin()
  }

  property FileView savedFile: FileView {
    path: root.savedPath
    printErrors: false
    blockLoading: true
    watchChanges: true

    onFileChanged: root.reloadSaved()
    Component.onCompleted: root.reloadSaved()
  }
}
