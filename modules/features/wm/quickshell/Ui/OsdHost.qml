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

  // The names Omarchy's OSD accepts, plus the literal glyph fallback. Keeping
  // the names means a script written for one shell reads the same here.
  function glyphFor(name, percent) {
    const key = String(name || "").toLowerCase()

    if (key === "volume-muted" || key === "volume-mute" || key === "muted" || key === "mute") return Util.volumeMute
    if (key === "volume-low" || key === "volume-medium") return Util.volumeLow
    if (key === "volume-high" || key === "volume") return Util.volumeHigh

    if (key === "microphone-muted" || key === "microphone-off" || key === "mic-muted" || key === "mic-off") return Util.micOff
    if (key === "microphone" || key === "mic") return Util.micOn

    if (key === "brightness" || key === "display") return Util.sun
    if (key === "keyboard") return Util.keyboard

    // The global tiling/floating switch, read back from LayoutModeHost.
    if (key === "layout-tiling" || key === "tiling") return Util.tiling
    if (key === "layout-floating" || key === "floating") return Util.floating

    if (key === "media" || key === "player" || key === "media-source" || key === "player-source") return Util.media
    if (key === "media-play" || key === "player-play") return Util.mediaPlay
    if (key === "media-pause" || key === "player-pause") return Util.mediaPause
    if (key === "media-next" || key === "player-next") return Util.mediaNext
    if (key === "media-previous" || key === "player-previous") return Util.mediaPrevious

    if (key.length > 0) return name
    if (percent <= 0) return Util.volumeMute
    if (percent <= 66) return Util.volumeLow
    return Util.volumeHigh
  }

  // A level is read at a glance; a message is read as a sentence. One and a
  // half seconds could hold "42%" but not a track title, and a notice that
  // leaves before it is finished is not a readout.
  function readableDuration(message) {
    const length = String(message || "").length
    return Math.min(4000, Math.max(1400, 700 + length * 35))
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    const raw = String(rawValue === undefined ? "" : rawValue)
    const parsed = parseInt(raw, 10)
    const max = Math.max(1, parseInt(String(rawMax === undefined ? "100" : rawMax), 10))

    // A value with no message is a level; a message with no value is a notice.
    // The message itself wins when both are supplied.
    const progress = raw !== "" && !isNaN(parsed) && String(rawMessage || "") === ""
    const value = progress ? Math.max(0, Math.min(max, parsed)) : 0
    const percent = progress ? Math.round(value * 100 / max) : -1
    const message = String(rawMessage || (progress ? (rawProgressText || percent + "%") : ""))

    // An explicit duration — including zero, which means "until dismissed" —
    // wins. Otherwise the readout stays long enough for its own text.
    const requested = String(rawDuration === undefined ? "" : rawDuration).trim()
    const explicit = parseInt(requested, 10)
    const duration = requested !== "" && !isNaN(explicit)
      ? Math.max(0, explicit)
      : (progress ? 1200 : root.readableDuration(message))

    root.iconKey = String(iconName || "").toLowerCase()
    root.icon = root.glyphFor(iconName, percent)
    root.hasProgress = progress
    root.value = value
    root.maxValue = max
    root.message = message
    root.duration = duration
    root.opened = true

    // A zero duration is a readout that stays until something closes it.
    if (root.duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function showPayload(raw) {
    try {
      const payload = JSON.parse(String(raw || "{}"))
      root.show(
        payload.icon || "",
        payload.message || "",
        payload.value === undefined ? "" : String(payload.value),
        payload.max === undefined ? "100" : String(payload.max),
        payload.progressText || "",
        payload.duration === undefined ? "" : String(payload.duration)
      )
    } catch (e) {
      console.warn("osd: could not parse payload: " + e)
    }
  }

  function hide() {
    root.opened = false
    hideTimer.stop()
  }

  function showVolume() {
    if (!root.armed || !root.audio) return

    const percent = Math.round(root.audio.volume * 100)
    const muted = root.audio.muted
    const icon = muted || percent === 0
      ? "volume-muted"
      : (percent > 66 ? "volume-high" : "volume-low")

    root.show(icon, "", percent, 100, muted ? "Muted" : percent + "%", 1200)
  }

  function showMicrophone() {
    if (!root.armed || !root.inputAudio) return

    const percent = Math.round(root.inputAudio.volume * 100)
    const muted = root.inputAudio.muted

    // The mic glyph already says which device this is; "Muted" says what
    // changed, and a live mic is more useful as a level than as "on".
    root.show(muted ? "microphone-muted" : "microphone", "", percent, 100,
      muted ? "Muted" : percent + "%", 1200)
  }

  // The watched file is only a trigger: the reading itself is taken through
  // brightnessctl below, because a change reaches the watcher before the
  // reloaded contents do and reading then reports the value before it.
  function showBrightness() {
    if (!root.armed || root.backlightDir === "") return
    brightnessProbe.running = true
  }

  // Volume arrives through the sink's volume and mute, either of which can
  // change on its own; both end up reporting the same readout.
  property Connections audioWatch: Connections {
    target: root.audio
    function onVolumesChanged() { root.showVolume() }
    function onMutedChanged() { root.showVolume() }
  }

  property Connections microphoneWatch: Connections {
    target: root.inputAudio
    function onVolumesChanged() { root.showMicrophone() }
    function onMutedChanged() { root.showMicrophone() }
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

  // The backlight device is discovered rather than named: the old hardcoded
  // `amdgpu_bl1` was true only on one machine. As with the reading itself, the
  // file is only a trigger and the value comes from brightnessctl.
  property string backlightDir: ""

  property Process backlightFind: Process {
    running: true
    command: ["sh", "-c", "ls -d /sys/class/backlight/* 2>/dev/null | head -n 1"]

    stdout: StdioCollector {
      onStreamFinished: root.backlightDir = String(this.text).trim()
    }
  }

  property FileView brightnessFile: FileView {
    path: root.backlightDir !== "" ? root.backlightDir + "/brightness" : ""
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: root.showBrightness()
  }

  // Machine readable, so one call carries both the reading and its scale:
  // device,class,current,percent%,max
  property Process brightnessProbe: Process {
    command: ["brightnessctl", "--machine-readable"]

    stdout: StdioCollector {
      onStreamFinished: {
        const percent = parseInt(String(this.text.trim().split(",")[3] || "").replace("%", ""), 10)
        if (isFinite(percent)) root.show("brightness", "", percent, 100, percent + "%", 1200)
      }
    }
  }

  property Timer armTimer: Timer {
    interval: 1500
    running: true
    onTriggered: root.armed = true
  }

  property Timer hideTimer: Timer {
    interval: root.duration
    onTriggered: root.opened = false
  }
}
