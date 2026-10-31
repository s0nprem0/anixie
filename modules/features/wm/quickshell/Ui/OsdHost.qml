pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

// The on-screen display: a short readout for a change the desktop just made.
//
// It is driven by state rather than by a CLI, so it also appears for changes
// that came from somewhere other than a key — a slider in a panel, or a client
// adjusting its own stream. The same API is exposed over IPC, so a script can
// ask for an icon, a message or a progress bar without growing a card of its
// own.
//
// The interface is deliberately the one Omarchy's OSD uses: an icon key, an
// optional message, an optional value/max pair and a duration. A readout with a
// value is a progress bar; one without is just an icon and message.
QtObject {
  id: root

  property bool opened: false
  property string icon: ""
  property string iconKey: ""
  property string message: ""
  property bool hasProgress: true
  property int value: 0
  property int maxValue: 100
  property int duration: 1200

  // The output the OSD should appear on. Empty means the focused screen,
  // which is the default for keyboard-driven changes.
  property string screenName: ""

  // A user-chosen preferred screen for OSDs that have no clear origin.
  // Empty falls back to the focused screen.
  property string preferredScreen: ""

  // Where the OSD sits on the screen: "bottom" (default), "top", or "bar"
  // (follow the bar's edge).
  property string position: "bottom"

  // Auto-scale duration by screen size. When off, durationScale is used.
  property bool autoDuration: true
  property real durationScale: 1.0

  // Media readouts are allowed to be wider than a percentage: the message is a
  // track title rather than "42%".
  readonly property bool mediaOsd: root.iconKey.indexOf("media") === 0
    || root.iconKey.indexOf("player") === 0

  // The first value each watcher delivers is the current one, not a change, so
  // they stay quiet until the initial reads have landed. Otherwise every login
  // opens with a volume display nobody asked for.
  property bool armed: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var inputAudio: source ? source.audio : null

  // ---- validation helpers ----

  function parseInteger(text) {
    const s = String(text === undefined || text === null ? "" : text).trim()
    if (s === "") return null
    if (!/^[+-]?\d+$/.test(s)) return null
    const n = Number(s)
    if (!Number.isFinite(n)) return null
    return n
  }

  function parseDuration(text) {
    const s = String(text === undefined || text === null ? "" : text).trim()
    if (s === "") return null
    if (!/^[+-]?\d+$/.test(s)) return null
    const n = Number(s)
    if (!Number.isFinite(n) || n < 0) return null
    return n
  }

  function safeDurationScale(scale) {
    const n = Number(scale)
    if (!Number.isFinite(n)) return 1
    return Math.max(0.25, Math.min(4, n))
  }

  function safeAutoScale(screen) {
    if (!screen) return 1
    const width = Number(screen.width)
    if (!Number.isFinite(width) || width <= 0) return 1
    if (width >= 2560) return 1.25
    if (width <= 1600) return 0.9
    return 1.0
  }

  function resolveScreen(requested) {
    const name = String(requested === undefined || requested === null ? "" : requested).trim()
    if (name !== "") {
      const found = Screens.byName(name)
      if (found) return found
    }

    const preferred = String(root.preferredScreen || "").trim()
    if (preferred !== "") {
      const found = Screens.byName(preferred)
      if (found) return found
    }

    return Screens.focused
  }

  // The names Omarchy's OSD accepts, plus the literal glyph fallback. Keeping
  // the names means a script written for one shell reads the same here.
  function glyphFor(name, percent) {
    const key = String(name === undefined || name === null ? "" : name).toLowerCase()

    if (key === "") return ""

    if (key === "volume-muted" || key === "volume-mute" || key === "muted" || key === "mute") return Util.volumeMute
    if (key === "volume-low" || key === "volume-medium") return Util.volumeLow
    if (key === "volume-high" || key === "volume") return Util.volumeHigh

    if (key === "microphone-muted" || key === "microphone-off" || key === "mic-muted" || key === "mic-off") return Util.micOff
    if (key === "microphone" || key === "mic") return Util.micOn

    if (key === "brightness" || key === "display") return Util.sun
    if (key === "keyboard") return Util.keyboard
    if (key === "nightlight") return Util.moon

    // The global tiling/floating switch, read back from LayoutModeHost.
    if (key === "layout-tiling" || key === "tiling") return Util.tiling
    if (key === "layout-floating" || key === "floating") return Util.floating

    if (key === "media" || key === "player" || key === "media-source" || key === "player-source") return Util.media
    if (key === "media-play" || key === "player-play") return Util.mediaPlay
    if (key === "media-pause" || key === "player-pause") return Util.mediaPause
    if (key === "media-next" || key === "player-next") return Util.mediaNext
    if (key === "media-previous" || key === "player-previous") return Util.mediaPrevious

    if (key.length > 0) return name
    return ""
  }

  // A level is read at a glance; a message is read as a sentence. One and a
  // half seconds could hold "42%" but not a track title, and a notice that
  // leaves before it is finished is not a readout.
  function readableDuration(message) {
    const text = String(message === undefined || message === null ? "" : message)
    const length = text.length
    const duration = 700 + length * 35
    return Math.min(4000, Math.max(1400, duration))
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, rawScreen) {
    root.hideTimer.stop()

    const requestedScreen = (rawScreen === undefined || rawScreen === null)
      ? ""
      : String(rawScreen).trim()
    // Keep the public property clean: an invalid or empty request does not leave
    // a stale screen name behind.
    root.screenName = requestedScreen !== "" && Screens.byName(requestedScreen)
      ? requestedScreen
      : ""

    const message = String(rawMessage === undefined || rawMessage === null ? "" : rawMessage)
    const raw = String(rawValue === undefined || rawValue === null ? "" : rawValue)
    const parsedValue = root.parseInteger(raw)
    const parsedMax = root.parseInteger(rawMax === undefined ? "100" : rawMax)
    const max = parsedMax === null ? 100 : Math.max(1, parsedMax)

    // A value with no message is a level; a message with no value is a notice.
    // The message itself wins when both are supplied.
    const progress = raw !== "" && parsedValue !== null && message === ""
    const value = progress ? Math.max(0, Math.min(max, parsedValue)) : 0
    const percent = progress ? Math.round(value * 100 / max) : -1

    const progressText = (rawProgressText === undefined || rawProgressText === null)
      ? ""
      : String(rawProgressText)
    const progressMessage = progress
      ? (progressText !== "" ? progressText : (percent + "%"))
      : ""
    const finalMessage = message !== "" ? message : progressMessage

    const requested = String(rawDuration === undefined || rawDuration === null ? "" : rawDuration).trim()
    const explicit = requested === "" ? null : root.parseDuration(requested)
    const screen = root.resolveScreen(requestedScreen)
    const autoScale = root.autoDuration
      ? root.safeAutoScale(screen)
      : root.safeDurationScale(root.durationScale)

    const baseDuration = progress ? 1200 : root.readableDuration(finalMessage)
    let duration = explicit !== null
      ? explicit
      : Math.round(baseDuration * autoScale)

    if (!Number.isFinite(duration) || duration < 0) duration = baseDuration
    if (!Number.isFinite(duration) || duration < 0) duration = 1200

    const iconKey = String(iconName === undefined || iconName === null ? "" : iconName).toLowerCase()

    root.iconKey = iconKey
    if (iconKey === "") {
      root.icon = progress
        ? (percent <= 0 ? Util.volumeMute : (percent <= 66 ? Util.volumeLow : Util.volumeHigh))
        : ""
    } else {
      root.icon = root.glyphFor(iconName, percent)
    }

    root.hasProgress = progress
    root.value = value
    root.maxValue = max
    root.message = finalMessage
    root.duration = duration
    root.opened = true

    // A zero duration is a readout that stays until something closes it.
    if (root.duration > 0) root.hideTimer.restart()
    else root.hideTimer.stop()
  }

  function showPayload(raw) {
    try {
      const payload = JSON.parse(String(raw === undefined || raw === null ? "{}" : raw))
      root.show(
        payload.icon === undefined ? "" : payload.icon,
        payload.message === undefined ? "" : payload.message,
        payload.value === undefined ? "" : String(payload.value),
        payload.max === undefined ? "100" : String(payload.max),
        payload.progressText === undefined ? "" : payload.progressText,
        payload.duration === undefined ? "" : String(payload.duration),
        payload.screen === undefined
          ? (payload.screen === null ? "" : (root.preferredScreen || ""))
          : String(payload.screen || "")
      )
    } catch (e) {
      console.warn("osd: could not parse payload: " + e)
    }
  }

  function hide() {
    root.opened = false
    root.hideTimer.stop()
  }

  function showVolume() {
    if (!root.armed || !root.audio) return

    const percent = Math.round(root.audio.volume * 100)
    const muted = root.audio.muted
    const icon = muted || percent === 0
      ? "volume-muted"
      : (percent > 66 ? "volume-high" : "volume-low")

    root.show(icon, "", percent, 100, muted ? "Muted" : percent + "%", 1200, root.preferredScreen)
  }

  function showMicrophone() {
    if (!root.armed || !root.inputAudio) return

    const percent = Math.round(root.inputAudio.volume * 100)
    const muted = root.inputAudio.muted

    // The mic glyph already says which device this is; "Muted" says what
    // changed, and a live mic is more useful as a level than as "on".
    root.show(muted ? "microphone-muted" : "microphone", "", percent, 100,
      muted ? "Muted" : percent + "%", 1200, root.preferredScreen)
  }

  // The watched file is only a trigger: the reading itself is taken through
  // brightnessctl below, because a change reaches the watcher before the
  // reloaded contents do and reading then reports the value before it.
  function showBrightness() {
    if (!root.armed || root.backlightDir === "") return

    if (root.brightnessProbe.running) root.brightnessProbe.running = false

    root.brightnessToken += 1
    root.brightnessActiveToken = root.brightnessToken
    root.brightnessProbe.running = true
  }

  // Volume arrives through the sink's volume and mute, either of which can
  // change on its own; both end up reporting the same readout.
  property Connections audioWatch: Connections {
    target: root.audio
    function onVolumesChanged() { root.volumeNotifyTimer.restart() }
    function onMutedChanged() { root.volumeNotifyTimer.restart() }
  }

  property Connections microphoneWatch: Connections {
    target: root.inputAudio
    function onVolumesChanged() { root.microphoneNotifyTimer.restart() }
    function onMutedChanged() { root.microphoneNotifyTimer.restart() }
  }

  // Track both default nodes so their audio properties stay available as
  // devices are added, removed or selected.
  property PwObjectTracker audioTracker: PwObjectTracker {
    objects: {
      const nodes = []
      if (root.sink) nodes.push(root.sink)
      if (root.source) nodes.push(root.source)
      return nodes
    }
  }

  property Timer volumeNotifyTimer: Timer {
    interval: 50
    onTriggered: root.showVolume()
  }

  property Timer microphoneNotifyTimer: Timer {
    interval: 50
    onTriggered: root.showMicrophone()
  }

  // The backlight device is discovered rather than named: the old hardcoded
  // `amdgpu_bl1` was true only on one machine. As with the reading itself, the
  // file is only a trigger and the value comes from brightnessctl.
  property string backlightDir: ""

  property Process backlightFind: Process {
    running: false
    command: ["sh", "-c", "ls -d /sys/class/backlight/* 2>/dev/null | sort | head -n 1"]

    stdout: StdioCollector {
      onStreamFinished: root.backlightDir = String(this.text || "").trim()
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) root.backlightDir = ""
    }
  }

  property FileView brightnessFile: FileView {
    path: root.backlightDir !== "" ? root.backlightDir + "/brightness" : ""
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: root.showBrightness()
    onLoadFailed: function (error) {
      root.backlightDir = ""
      root.backlightFind.running = true
    }
  }

  // Machine readable, so one call carries both the reading and its scale:
  // device,class,current,percent%,max
  property int brightnessToken: 0
  property int brightnessActiveToken: 0
  property int brightnessProcessedToken: 0
  property string brightnessOutput: ""

  property Process brightnessProbe: Process {
    command: ["brightnessctl", "--machine-readable"]

    stdout: StdioCollector {
      onStreamFinished: root.brightnessOutput = String(this.text || "")
    }

    onExited: function (exitCode, exitStatus) {
      if (root.brightnessToken !== root.brightnessActiveToken) return
      if (root.brightnessProcessedToken === root.brightnessActiveToken) return
      root.brightnessProcessedToken = root.brightnessActiveToken

      if (exitCode !== 0) return

      const lines = String(root.brightnessOutput || "").trim().split(/\r?\n/)
      const raw = lines.length > 0 ? lines[0].trim() : ""
      if (raw === "") return

      const parts = raw.split(",")
      if (parts.length < 4) return

      const percentText = String(parts[3] || "").trim().replace("%", "")
      const percent = root.parseInteger(percentText)
      if (percent === null) return

      const clamped = Math.max(0, Math.min(100, percent))
      root.show("brightness", "", clamped, 100, clamped + "%", 1200, root.preferredScreen)
    }

  }

  property Connections pipewireReady: Connections {
    target: Pipewire
    function onReadyChanged() {
      if (Pipewire.ready) root.armed = true
    }
  }

  property Timer hideTimer: Timer {
    interval: root.duration
    onTriggered: root.opened = false
  }

  Component.onCompleted: {
    root.backlightFind.running = true
    if (Pipewire.ready) root.armed = true
  }
}
