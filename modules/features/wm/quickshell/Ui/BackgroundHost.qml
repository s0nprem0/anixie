pragma Singleton

pragma ComponentBehavior: Bound
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

  function safeEnv(name, fallback) {
    let v = ""
    try {
      v = Quickshell.env(name)
    } catch (e) {
      v = ""
    }
    if (v === undefined || v === null) v = ""
    if (String(v).trim() !== "") return String(v)
    if (fallback === undefined || fallback === null) return ""
    return String(fallback)
  }

  readonly property string homeDir: {
    const h = root.safeEnv("HOME", "")
    if (h !== "") return h
    return ""
  }

  readonly property string xdgStateHome: {
    const x = root.safeEnv("XDG_STATE_HOME", "")
    if (x !== "") return x
    if (root.homeDir !== "") return root.homeDir + "/.local/state"
    return ""
  }

  readonly property string stateBase: {
    if (root.xdgStateHome !== "") return root.xdgStateHome + "/anixie/theme"
    // If both unavailable, fall back to relative-like safe paths under /tmp to avoid crashing
    return "/tmp/anixie/theme"
  }

  readonly property string statePath: root.stateBase + "/background.json"
  readonly property string legacyPath: root.stateBase + "/background"
  readonly property string rotationPath: root.stateBase + "/rotation"

  // Monotonic revision incremented only on accepted valid transitions
  property int revision: 0

  // Normalized state
  property string fallbackPath: ""
  property bool fallbackVideo: false
  property string fallbackPoster: ""

  property var outputsMap: ({}) // name -> { path, video, poster }

  property int applyGeneration: 0
  property int lastAppliedGeneration: -1

  // Operation serialization/coalescing state
  property bool operationRunning: false
  property bool operationPending: false
  property var pendingOperation: null // function or null

  // Flags to track if we've loaded valid JSON state
  property bool hasValidJsonState: false
  property bool hasLegacyState: false

  // For retry/startup
  property int attempts: 0

  function isNonEmptyString(v) {
    return typeof v === "string" && v.trim() !== ""
  }

  function normalizeOutputEntry(entry) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null
    if (typeof entry.path !== "string") return null
    const path = entry.path
    if (path.trim() === "") return null
    const out = {
      path: path,
      video: !!entry.video,
      poster: typeof entry.poster === "string" ? entry.poster : ""
    }
    return out
  }

  function normalizeDocument(raw) {
    let data
    try {
      if (typeof raw !== "string") {
        if (raw === undefined || raw === null) return null
        // try to stringify if it's an object-like? but callers pass text
        data = raw
      } else {
        data = JSON.parse(raw)
      }
    } catch (e) {
      return null
    }
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      return null
    }
    const fallbackRaw = data.fallback
    let fallback = null
    if (fallbackRaw !== undefined && fallbackRaw !== null) {
      if (typeof fallbackRaw !== "object" || Array.isArray(fallbackRaw)) {
        return null
      }
      if (typeof fallbackRaw.path === "string" && fallbackRaw.path.trim() !== "") {
        fallback = {
          path: fallbackRaw.path,
          video: !!fallbackRaw.video,
          poster: typeof fallbackRaw.poster === "string" ? fallbackRaw.poster : ""
        }
      } else {
        // fallback must be valid if present? require path non-empty
        return null
      }
    }

    const outputsRaw = data.outputs
    if (outputsRaw !== undefined && outputsRaw !== null) {
      if (typeof outputsRaw !== "object" || Array.isArray(outputsRaw)) {
        return null
      }
    }

    const nextMap = {}
    if (outputsRaw && typeof outputsRaw === "object" && !Array.isArray(outputsRaw)) {
      for (const name in outputsRaw) {
        if (!Object.prototype.hasOwnProperty.call(outputsRaw, name)) continue
        const normName = String(name)
        if (normName.trim() === "") continue // reject bad output names
        const normEntry = normalizeOutputEntry(outputsRaw[name])
        if (normEntry === null) {
          // reject malformed document entirely
          return null
        }
        nextMap[normName] = normEntry
      }
    }

    // If fallback missing entirely, that's allowed? But need to be consistent with structure
    // Build normalized document
    const normalized = {
      outputs: nextMap,
      fallback: fallback !== null ? fallback : { path: "", video: false, poster: "" }
    }
    return normalized
  }

  function adopt(raw) {
    const normalized = root.normalizeDocument(raw)
    if (normalized === null) {
      return false
    }
    // Apply normalized state
    root.outputsMap = normalized.outputs || ({})
    root.fallbackPath = normalized.fallback && typeof normalized.fallback.path === "string" ? normalized.fallback.path : ""
    root.fallbackVideo = normalized.fallback ? !!normalized.fallback.video : false
    root.fallbackPoster = normalized.fallback && typeof normalized.fallback.poster === "string" ? normalized.fallback.poster : ""
    if (root.fallbackPath === "") {
      // Try to find from outputs if fallback missing/empty
      for (const name in root.outputsMap) {
        const entry = root.outputsMap[name]
        if (entry && entry.path) {
          root.fallbackPath = entry.path
          root.fallbackVideo = !!entry.video
          root.fallbackPoster = entry.poster || ""
          break
        }
      }
    }
    root.hasValidJsonState = true
    root.revision += 1
    return true
  }

  function adoptLegacy(raw) {
    // Only migrate if we don't have valid JSON state
    if (root.hasValidJsonState) {
      return false
    }
    const text = String(raw || "")
    const lines = text.split("\n").map(function (line) { return line.trim() })
      .filter(function (line) { return line !== "" })
    if (lines.length === 0) {
      // Empty legacy file is not a valid selection - do not migrate
      return false
    }
    root.outputsMap = ({})
    root.fallbackVideo = lines[0] === "video"
    if (root.fallbackVideo) {
      root.fallbackPath = lines[1] || ""
    } else {
      root.fallbackPath = lines[0] || ""
    }
    root.fallbackPoster = ""
    root.hasLegacyState = true
    root.revision += 1
    return true
  }

  function buildMapObject() {
    return {
      outputs: root.outputsMap,
      fallback: {
        path: root.fallbackPath,
        video: !!root.fallbackVideo,
        poster: root.fallbackPoster || ""
      }
    }
  }

  function persistMap(mapObj) {
    try {
      const json = JSON.stringify(mapObj, null, 2) + "\n"
      if (root.stateFile.setText) {
        root.stateFile.setText(json)
        return true
      }
    } catch (e) {
      // surface failure
    }
    return false
  }

  function applyMap(map) {
    // map can come from external callers - validate and normalize strictly
    if (!map || typeof map !== "object" || Array.isArray(map)) {
      return false
    }
    // Direct validation similar to normalizeDocument
    let data = map
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      return false
    }
    const fallbackRaw = data.fallback
    if (!fallbackRaw || typeof fallbackRaw !== "object" || Array.isArray(fallbackRaw)) {
      return false
    }
    if (typeof fallbackRaw.path !== "string" || fallbackRaw.path.trim() === "") {
      return false
    }
    const outputsRaw = data.outputs
    if (outputsRaw !== undefined && outputsRaw !== null) {
      if (typeof outputsRaw !== "object" || Array.isArray(outputsRaw)) {
        return false
      }
    }
    const nextMap = {}
    if (outputsRaw && typeof outputsRaw === "object" && !Array.isArray(outputsRaw)) {
      for (const name in outputsRaw) {
        if (!Object.prototype.hasOwnProperty.call(outputsRaw, name)) continue
        const normName = String(name)
        if (normName.trim() === "") return false
        const entry = outputsRaw[name]
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) return false
        if (typeof entry.path !== "string" || entry.path.trim() === "") return false
        nextMap[normName] = {
          path: entry.path,
          video: !!entry.video,
          poster: typeof entry.poster === "string" ? entry.poster : ""
        }
      }
    }
    root.outputsMap = nextMap
    root.fallbackPath = fallbackRaw.path
    root.fallbackVideo = !!fallbackRaw.video
    root.fallbackPoster = typeof fallbackRaw.poster === "string" ? fallbackRaw.poster : ""
    root.hasValidJsonState = true
    root.revision += 1
    const ok = root.persistMap(root.buildMapObject())
    return ok
  }

  function set(path) {
    const value = String(path || "").trim()
    if (value === "") return false
    let res = false
    root.enqueueOperation(function() {
      res = root.applyMap({
        outputs: {},
        fallback: { path: value, video: false, poster: "" }
      })
    })
    return res
  }

  function setVideo(path) {
    const value = String(path || "").trim()
    if (value === "") return false
    let res = false
    root.enqueueOperation(function() {
      res = root.applyMap({
        outputs: {},
        fallback: { path: value, video: true, poster: "" }
      })
    })
    return res
  }

  function setOutput(output, path, video, poster) {
    const name = String(output || "").trim()
    const value = String(path || "").trim()
    if (name === "" || value === "") return false

    let res = false
    root.enqueueOperation(function() {
      const next = {}
      for (const key in root.outputsMap) {
        if (Object.prototype.hasOwnProperty.call(root.outputsMap, key)) {
          next[key] = root.outputsMap[key]
        }
      }
      next[name] = { path: value, video: !!video, poster: typeof poster === "string" ? poster : "" }
      res = root.applyMap({
        outputs: next,
        fallback: { path: root.fallbackPath, video: root.fallbackVideo, poster: root.fallbackPoster || "" }
      })
    })
    return res
  }

  function reload() {
    try { root.stateFile.reload() } catch (e) {}
    try { root.legacyFile.reload() } catch (e) {}
    try { root.rotationFile.reload() } catch (e) {}
  }

  // Backwards compatible accessors
  function entryFor(screenName) {
    const name = String(screenName || "")
    if (name !== "" && root.outputsMap[name] !== undefined) {
      const e = root.outputsMap[name]
      if (e && typeof e === "object") return e
    }
    return { path: root.fallbackPath, video: !!root.fallbackVideo, poster: root.fallbackPoster || "" }
  }

  function pathFor(screenName) {
    const e = root.entryFor(screenName)
    return e && e.path ? e.path : ""
  }

  function videoFor(screenName) {
    const e = root.entryFor(screenName)
    return !!(e && e.video)
  }

  function posterFor(screenName) {
    const e = root.entryFor(screenName)
    return e && e.poster ? e.poster : ""
  }

  // Public properties for compatibility
  readonly property var outputs: root.outputsMap
  readonly property string path: root.fallbackPath
  readonly property bool video: root.fallbackVideo
  readonly property string poster: root.fallbackPoster

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      try {
        const txt = root.stateFile.text ? root.stateFile.text() : ""
        root.adopt(txt)
      } catch (e) {
        // If read fails, don't overwrite state
      }
    }
    onLoadFailed: function(error) {
      // distinguish missing/unavailable
    }
    onFileChanged: {
      try { root.stateFile.reload() } catch (e) {}
    }
    onSaved: {
      // write completed
    }
    onSaveFailed: function(error) {
      console.warn("quickshell: background state write failed")
    }
  }

  property FileView legacyFile: FileView {
    path: Qt.resolvedUrl(root.legacyPath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      try {
        if (root.hasValidJsonState) {
          return
        }
        if (root.path === "" && Object.keys(root.outputsMap || {}).length === 0) {
          const txt = root.legacyFile.text ? root.legacyFile.text() : ""
          root.adoptLegacy(txt)
        } else if (!root.hasValidJsonState && !root.hasLegacyState && root.path === "" && Object.keys(root.outputsMap || {}).length === 0) {
          const txt = root.legacyFile.text ? root.legacyFile.text() : ""
          root.adoptLegacy(txt)
        }
      } catch (e) {
      }
    }
    onLoadFailed: function(error) {
    }
    onFileChanged: {
      try { root.legacyFile.reload() } catch (e) {}
    }
  }

  // ---- output hotplug ----
  readonly property string monitorSignature: {
    const all = Quickshell.screens || []
    const out = []
    for (let i = 0; i < all.length; i++) {
      const s = all[i]
      const name = s && s.name ? String(s.name) : ""
      const w = s && s.width !== undefined && s.width !== null ? s.width : ""
      const h = s && s.height !== undefined && s.height !== null ? s.height : ""
      if (name === "") continue
      out.push(name + ":" + w + "x" + h)
    }
    out.sort()
    return out.join(",")
  }

  onMonitorSignatureChanged: {
    if (root.monitorSignature === "") return
    root.scheduleMonitorApply()
  }

  function scheduleMonitorApply() {
    // coalesce repeated monitor changes
    root.monitorApplyTimer.restart()
  }

  property Timer monitorApplyTimer: Timer {
    interval: 900
    repeat: false
    running: false
    onTriggered: {
      root.enqueueOperation(function() {
        if (root.monitorApply.running) {
          root.monitorApply.running = false
        }
        root.monitorApply.running = true
      })
    }
  }

  property Process monitorApply: Process {
    command: ["wallpaper", "apply"]
    running: false
    onExited: function(exitCode, exitStatus) {
      root.onOperationFinished()
    }
  }

  // ---- automatic rotation ----
  readonly property string rotationPathResolved: root.rotationPath
  property int rotationMinutes: 0
  property int maxRotationMinutes: 1440

  property FileView rotationFile: FileView {
    path: Qt.resolvedUrl(root.rotationPathResolved)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      try {
        const txt = root.rotationFile.text ? String(root.rotationFile.text() || "") : ""
        const trimmed = txt.trim()
        // Must be complete non-negative integer (no partial matches)
        if (/^[0-9]+$/.test(trimmed)) {
          const value = parseInt(trimmed, 10)
          if (!isNaN(value) && value >= 0) {
            if (value > root.maxRotationMinutes) {
              root.rotationMinutes = root.maxRotationMinutes
            } else {
              root.rotationMinutes = value
            }
          } else {
            root.rotationMinutes = 0
          }
        } else if (trimmed === "" || trimmed === "0") {
          root.rotationMinutes = 0
        } else {
          // try strict parse
          const m = trimmed.match(/^\d+$/)
          if (m) {
            const value = parseInt(m[0], 10)
            root.rotationMinutes = (value >= 0 && value <= root.maxRotationMinutes) ? value : (value < 0 ? 0 : root.maxRotationMinutes)
          } else {
            root.rotationMinutes = 0
          }
        }
        // Update timer interval
        root.rotationTimer.interval = Math.max(1, root.rotationMinutes) * 60000
        root.rotationTimer.running = root.rotationMinutes > 0 && !root.rotation.running
      } catch (e) {
        root.rotationMinutes = 0
      }
    }
    onFileChanged: {
      try { root.rotationFile.reload() } catch (e) {}
    }
  }

  property Timer rotationTimer: Timer {
    interval: Math.max(1, root.rotationMinutes) * 60000
    repeat: true
    running: root.rotationMinutes > 0 && !root.rotation.running
    onTriggered: {
      if (root.rotationMinutes <= 0) {
        root.rotationTimer.running = false
        return
      }
      root.enqueueOperation(function() {
        if (root.rotation.running) {
          // don't restart aggressively
        }
        root.rotation.running = true
      })
    }
  }

  property Process rotation: Process {
    command: ["wallpaper", "rotate"]
    running: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        // avoid uncontrolled retry loop - just finish operation
      }
      root.onOperationFinished()
    }
  }

  // Operation coordinator
  function enqueueOperation(op) {
    if (typeof op !== "function") return
    if (root.operationRunning) {
      root.operationPending = true
      root.pendingOperation = op
      return
    }
    root.runOperation(op)
  }

  function runOperation(op) {
    root.operationRunning = true
    try {
      op()
    } catch (e) {
      root.operationRunning = false
      root.maybeRunPending()
      return
    }
    // If op started a process, we'll finish when process exits; otherwise finish now
    // Heuristic: check if any of our managed processes started running? They are set by op
    // For safety, if nothing running that we track, finish
    Qt.callLater(function() {
      if (!root.monitorApply.running && !root.rotation.running) {
        root.onOperationFinished()
      }
    })
  }

  function onOperationFinished() {
    // Don't finish if a managed process just started
    if (root.monitorApply.running || root.rotation.running) {
      return
    }
    root.operationRunning = false
    root.maybeRunPending()
  }

  function maybeRunPending() {
    if (root.operationPending && root.pendingOperation !== null && !root.operationRunning) {
      if (root.monitorApply.running || root.rotation.running) {
        return
      }
      const op = root.pendingOperation
      root.operationPending = false
      root.pendingOperation = null
      root.runOperation(op)
    }
  }

  property Timer settle: Timer {
    interval: 500
    repeat: true
    running: root.fallbackPath === "" && Object.keys(root.outputsMap || {}).length === 0 && root.attempts < 60
    onTriggered: {
      root.attempts += 1
      try { root.stateFile.reload() } catch (e) {}
      try { root.legacyFile.reload() } catch (e) {}
    }
  }
}
