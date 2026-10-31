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
  property string poster: ""
  property int revision: 0

  function entryFor(screenName) {
    const name = String(screenName || "")
    if (name !== "" && root.outputs[name] !== undefined) return root.outputs[name]
    return { path: root.path, video: root.video, poster: root.poster }
  }

  function pathFor(screenName) {
    return root.entryFor(screenName).path || ""
  }

  function videoFor(screenName) {
    return !!root.entryFor(screenName).video
  }

  // A still from a video, for the lock screen and any other surface that cannot
  // play it. Empty when the video has not been applied yet or ffmpeg failed.
  function posterFor(screenName) {
    return root.entryFor(screenName).poster || ""
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
          video: !!map[name].video,
          poster: typeof map[name].poster === "string" ? map[name].poster : ""
        }
      }
    }

    root.outputs = next
    root.path = typeof fallback.path === "string" ? fallback.path : ""
    root.video = !!fallback.video
    root.poster = typeof fallback.poster === "string" ? fallback.poster : ""
    if (root.path === "") {
      for (const name in next) {
        root.path = next[name].path
        root.video = next[name].video
        root.poster = next[name].poster
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
    root.poster = ""
    root.revision += 1
  }

  function applyMap(map) {
    root.outputs = map.outputs || ({})
    const fallback = map.fallback || {}
    root.path = fallback.path || ""
    root.video = !!fallback.video
    root.poster = fallback.poster || ""
    root.revision += 1
    root.stateFile.setText(JSON.stringify(map, null, 2) + "\n")
  }

  function set(path) {
    const value = String(path || "").trim()
    if (value === "") return
    root.applyMap({
      outputs: {},
      fallback: { path: value, video: false, poster: "" }
    })
  }

  function setVideo(path) {
    const value = String(path || "").trim()
    if (value === "") return
    root.applyMap({
      outputs: {},
      fallback: { path: value, video: true, poster: "" }
    })
  }

  function setOutput(output, path, video, poster) {
    const name = String(output || "")
    const value = String(path || "").trim()
    if (name === "" || value === "") return

    const next = {}
    for (const key in root.outputs) next[key] = root.outputs[key]
    next[name] = { path: value, video: !!video, poster: String(poster || "") }
    root.applyMap({
      outputs: next,
      fallback: { path: root.path, video: root.video, poster: root.poster }
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

  // ---- output hotplug ----
  //
  // A monitor that arrives or changes resolution needs its own generated
  // gradient, and a video output needs mpvpaper started on it. Hyprland does
  // not tell the wallpaper command, so the shell watches its own screen list
  // instead: Quickshell.screens is change-notifying, and the signature includes
  // the size so a resolution change counts as well.
  readonly property string monitorSignature: {
    const all = Quickshell.screens || []
    const out = []
    for (let i = 0; i < all.length; i++) {
      out.push(String(all[i].name) + ":" + all[i].width + "x" + all[i].height)
    }
    out.sort()
    return out.join(",")
  }

  onMonitorSignatureChanged: {
    if (root.monitorSignature === "") return
    // Hyprland and Quickshell do not update in the same event turn; a short
    // settle keeps one hotplug from applying twice.
    root.monitorApplyTimer.restart()
  }

  property Timer monitorApplyTimer: Timer {
    interval: 900
    repeat: false
    running: false
    onTriggered: {
      root.monitorApply.running = false
      root.monitorApply.running = true
    }
  }

  property Process monitorApply: Process {
    command: ["wallpaper", "apply"]
    running: false
  }

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
