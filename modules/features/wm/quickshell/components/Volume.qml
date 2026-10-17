import QtQuick
import ".."
import Quickshell
import Quickshell.Io

Text {
  id: root
  color: muted ? Theme.muted : Theme.fg
  font.family: "JetBrains Mono"
  font.pixelSize: 13

  property int level: -1
  property bool muted: false

  Process {
    id: probe
    running: true
    command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
    stdout: StdioCollector {
      onStreamFinished: {
        // wpctl reports a 0.0-1.0 float ("Volume: 0.45"), not a percentage,
        // and appends "[MUTED]" when the sink is silent.
        const raw = this.text.trim()
        const vol = raw.match(/[0-9]*\.?[0-9]+/)
        if (vol)
          root.level = Math.round(parseFloat(vol[0]) * 100)
        root.muted = /MUTED/.test(raw)
      }
    }
  }

  Timer {
    running: true
    interval: 2000
    triggeredOnStart: true
    onTriggered: { probe.running = false; probe.running = true }
  }

  text: level < 0 ? "" : (muted ? "VOL MUTE" : "VOL " + level + "%")
}