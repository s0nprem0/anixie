pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

// The on-screen display: a brief readout shown when output, input or screen
// brightness changes. Mute states use words as well as icons so they are clear
// at a glance.
//
// Driven by the state it reports rather than by a command, so it also appears
// for changes that came from somewhere other than a key — a slider in a panel,
// or a client adjusting its own stream. The reference drives its own from a CLI
// and so only covers the changes that go through it.
QtObject {
  id: root

  readonly property string backlightDevice: "amdgpu_bl1"

  property bool shown: false
  property string icon: ""
  property int percent: 0
  property string valueText: ""
  property bool muted: false

  // The first value each watcher delivers is the current one, not a change, so
  // they stay quiet until the initial reads have landed. Otherwise every login
  // opens with a volume display nobody asked for.
  property bool armed: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var inputAudio: source ? source.audio : null

  function reveal(nextIcon, nextPercent, nextValueText, nextMuted) {
    if (!root.armed) return

    root.icon = nextIcon
    root.percent = Math.max(0, Math.min(100, Math.round(nextPercent)))
    root.valueText = nextValueText
    root.muted = nextMuted
    root.shown = true
    hideTimer.restart()
  }

  function showVolume() {
    if (!root.audio) return

    const percent = Math.round(root.audio.volume * 100)
    const muted = root.audio.muted
    const icon = muted || percent === 0
      ? Util.volumeMute
      : (percent > 66 ? Util.volumeHigh : Util.volumeLow)

    root.reveal(icon, percent, muted ? "Muted" : percent + "%", muted)
  }

  function showMicrophone() {
    if (!root.inputAudio) return

    const percent = Math.round(root.inputAudio.volume * 100)
    const muted = root.inputAudio.muted
    const icon = muted ? Util.micOff : Util.micOn

    // The mic glyph already says which device this is; "Muted" says what
    // changed, and a live mic is more useful as a level than as "on".
    root.reveal(icon, percent, muted ? "Muted" : percent + "%", muted)
  }

  // The watched file is only a trigger: the reading itself is taken through
  // brightnessctl below, because a change reaches the watcher before the
  // reloaded contents do and reading then reports the value before it.
  function showBrightness() {
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

  property FileView brightnessFile: FileView {
    path: "/sys/class/backlight/" + root.backlightDevice + "/brightness"
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: root.showBrightness()
  }

  // Machine readable, so one call carries both the reading and its scale:
  // device,class,current,percent%,max
  property Process brightnessProbe: Process {
    command: ["brightnessctl", "--device", root.backlightDevice, "--machine-readable"]

    stdout: StdioCollector {
      onStreamFinished: {
        const percent = parseInt(String(this.text.trim().split(",")[3] || "").replace("%", ""), 10)
        if (isFinite(percent)) root.reveal(Util.sun, percent, percent + "%", false)
      }
    }
  }

  property Timer armTimer: Timer {
    interval: 1500
    running: true
    onTriggered: root.armed = true
  }

  property Timer hideTimer: Timer {
    interval: 1200
    onTriggered: root.shown = false
  }
}
