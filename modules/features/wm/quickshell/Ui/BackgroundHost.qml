pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop background: one entry per output, with a fallback for outputs
// that have no explicit choice.
//
// The `wallpaper` command resolves the whole map and writes it to
// background.json, then tells this object over IPC. The file is what a shell
// that starts later reads, which matters at login: the theme service and the
// shell both start at graphical-session.target, so either can win the race.
//
// The image itself is drawn by BackgroundSurface, one per output. Videos are
// drawn by mpvpaper and the shell's surface steps aside for those outputs.
QtObject {
  id: root

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/theme/background.json"
  readonly property string legacyPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/theme/background"

  property var outputs: ({})
  property string path: ""
  property bool video: false
  property int revision: 0

  function entryFor(screenName) {
    const name = String(screenName || "")
    if (name !== "" && root.outputs[name] !== undefined) return root.outputs[name]
    return { path: root.path, video: root.video }
  }

  function pathFor(screenName) {
    return root.entryFor(screenName).path || ""
  }

  function videoFor(screenName) {
    return !!root.entryFor(screenName).video
  }

  function adopt(raw) {
    let data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (e) {
      return false
    }
    if (!data || typeof data !== "object") return false

    const fallback = data.fallback || {}
    const map = data.outputs || {}
    const next = {}
    for (const name in map) {
      if (map[name] && typeof map[name].path === "string") {
        next[String(name)] = {
          path: map[name].path,
          video: !!map[name].video
        }
      }
    }

    root.outputs = next
    root.path = typeof fallback.path === "string" ? fallback.path : ""
    root.video = !!fallback.video
    if (root.path === "") {
      for (const name in next) {
        root.path = next[name].path
        root.video = next[name].video
        break
      }
    }
    root.revision += 1
    return true
  }

  function adoptLegacy(raw) {
    const lines = String(raw || "").split("\n").map(function (line) { return line.trim() })
      .filter(function (line) { return line !== "" })
    if (lines.length === 0) return

    root.outputs = ({})
    root.video = lines[0] === "video"
    root.path = root.video ? (lines[1] || "") : lines[0]
    root.revision += 1
  }

  function applyMap(map) {
    root.outputs = map.outputs || ({})
    const fallback = map.fallback || {}
    root.path = fallback.path || ""
    root.video = !!fallback.video
    root.revision += 1
    root.stateFile.setText(JSON.stringify(map, null, 2) + "\n")
  }

  function set(path) {
    const value = String(path || "").trim()
    if (value === "") return
    root.applyMap({
      outputs: {},
      fallback: { path: value, video: false }
    })
  }

  function setVideo(path) {
    const value = String(path || "").trim()
    if (value === "") return
    root.applyMap({
      outputs: {},
      fallback: { path: value, video: true }
    })
  }

  function setOutput(output, path, video) {
    const name = String(output || "")
    const value = String(path || "").trim()
    if (name === "" || value === "") return

    const next = {}
    for (const key in root.outputs) next[key] = root.outputs[key]
    next[name] = { path: value, video: !!video }
    root.applyMap({
      outputs: next,
      fallback: { path: root.path, video: root.video }
    })
  }

  function reload() {
    root.stateFile.reload()
    root.legacyFile.reload()
  }

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: root.adopt(root.stateFile.text())
    onFileChanged: root.stateFile.reload()
  }

  property FileView legacyFile: FileView {
    path: Qt.resolvedUrl(root.legacyPath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      if (root.path === "" && Object.keys(root.outputs).length === 0) {
        root.adoptLegacy(root.legacyFile.text())
      }
    }
    onFileChanged: root.legacyFile.reload()
  }

  property int attempts: 0

  property Timer settle: Timer {
    interval: 500
    repeat: true
    running: root.path === "" && Object.keys(root.outputs).length === 0 && root.attempts < 60
    onTriggered: {
      root.attempts += 1
      root.stateFile.reload()
      root.legacyFile.reload()
    }
  }
}
