pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import ".."

// The on-screen display: a brief readout shown when the volume or the screen
// brightness changes.
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

  // The first value each watcher delivers is the current one, not a change, so
  // they stay quiet until the initial reads have landed. Otherwise every login
  // opens with a volume display nobody asked for.
  property bool armed: false

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null

  function reveal(nextIcon, nextPercent) {
    if (!root.armed) return

    root.icon = nextIcon
    root.percent = Math.max(0, Math.min(100, Math.round(nextPercent)))
    root.shown = true
    hideTimer.restart()
  }

  function showVolume() {
    if (!root.audio) return

    const percent = Math.round(root.audio.volume * 100)
    const icon = root.audio.muted
      ? Util.volumeMute
      : (percent > 66 ? Util.volumeHigh : Util.volumeLow)

    root.reveal(icon, percent)
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
        if (isFinite(percent)) root.reveal(Util.sun, percent)
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
