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

  // The shipped file, and whatever the bar has saved over it. Both are read at
  // startup: the shipped one is a store path that cannot change without a
  // rebuild, and the saved one is this file's own output after that.
  property var builtin: root.fallback

  // The layout in use, once it is known. The saved file is read at startup; after
  // that this is the truth and every change writes it out. Watching the file and
  // re-reading it on every write raced the writes themselves — two widgets
  // dropped in quick succession kept only the second.
  property var state: null

  readonly property var config: root.state !== null ? root.state : root.builtin

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
    let raw = ""
    try {
      raw = root.savedFile.text()
    } catch (e) {
      raw = ""
    }

    if (raw.trim() === "") return

    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") root.state = parsed
    } catch (e) {
      console.warn("quickshell bar: the saved layout is not valid JSON, using bar.json")
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

  // ---- the manifest ----
  //
  // Where a widget goes when it is enabled and has never been on the bar. The
  // shipped layout decides the rest; this is only the answer to "put it back"
  // for the widgets the default no longer shows. Kept as data so adding one is a
  // line here rather than another branch in the bar.
  readonly property var defaults: {
    let raw = ""
    try {
      raw = root.modulesFile.text()
    } catch (e) {
      return ({})
    }

    try {
      const parsed = JSON.parse(raw)
      return parsed && typeof parsed === "object" ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function isEnabled(id) {
    for (const name in root.layout) {
      const list = root.layout[name]
      for (let i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === id) return true
      }
    }
    return false
  }

  // Off the bar, remembered with the place it came from so enabling it puts it
  // back there rather than at the end of a section.
  function disable(id) {
    if (!id || !root.isEnabled(id)) return

    const next = JSON.parse(JSON.stringify(root.config))
    next.layout = next.layout || {}

    let entry = null
    let from = ""
    let at = -1

    for (const name in next.layout) {
      const list = next.layout[name]
      for (let i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === id) {
          entry = list[i]
          from = name
          at = i
          list.splice(i, 1)
          break
        }
      }
      if (entry) break
    }

    if (!entry) return
    next.disabled = next.disabled || []
    next.disabled.push({ section: from, index: at, entry: entry })
    root.save(next)
  }

  // Back on the bar: where it was if it was put away, otherwise where the
  // manifest says.
  function enable(id) {
    if (!id || root.isEnabled(id)) return

    const next = JSON.parse(JSON.stringify(root.config))
    next.layout = next.layout || {}

    const parked = next.disabled || []
    let found = -1
    for (let i = 0; i < parked.length; i++) {
      if (parked[i] && parked[i].entry && parked[i].entry.id === id) {
        found = i
        break
      }
    }

    if (found >= 0) {
      const slot = parked[found]
      parked.splice(found, 1)
      next.disabled = parked

      const section = slot.section || "right"
      next.layout[section] = next.layout[section] || []
      const list = next.layout[section]
      list.splice(Math.max(0, Math.min(slot.index, list.length)), 0, slot.entry)
    } else {
      const section = root.defaults[id] || "right"
      next.layout[section] = next.layout[section] || []
      next.layout[section].push({ id: id })
    }

    root.save(next)
  }

  function setBackground(mode) {
    if (!mode) return
    const next = JSON.parse(JSON.stringify(root.config))
    next.background = String(mode)
    root.save(next)
  }

  function save(next) {
    // The in-memory layout moves immediately, before the file is written. The
    // write goes through a process and a file adapter, and a second move in that
    // window would otherwise read the layout from before the first — dropping two
    // widgets into the same section kept only the second.
    root.state = next
    root.savedText = JSON.stringify(next, null, 2) + "\n"

    // The directory is made first: a write into a directory that does not exist
    // yet is a drop that silently does nothing.
    mkdir.running = false
    mkdir.running = true
  }

  // Put the shipped layout back, by taking the saved one away.
  function reset() {
    root.state = null
    root.savedText = ""
    rm.running = false
    rm.running = true
  }

  // What was last written, so the write can be deferred until the directory
  // exists without losing a later change.
  property string savedText: ""

  property Process mkdir: Process {
    command: ["mkdir", "-p", root.stateDir]
    running: false
    onExited: {
      if (root.savedText !== "") root.savedFile.setText(root.savedText)
    }
  }

  property Process rm: Process {
    command: ["rm", "-f", root.savedPath]
    running: false
    onExited: root.savedText = ""
  }

  // A FileView held as a property rather than a child: a QtObject has no
  // default property, so a bare child declaration would never attach.
  property FileView modulesFile: FileView {
    path: Qt.resolvedUrl("modules.json")
    printErrors: false
    blockLoading: true
  }

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

    Component.onCompleted: root.reloadSaved()
  }
}
