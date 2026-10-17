import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Pipewire

// Volume readout backed by PipeWire directly. The node exposes volume and mute
// as properties that notify on change, so this needs no polling and no wpctl
// subprocess: a scroll on the bar writes straight back to the stream.
BarWidget {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null
  readonly property real volume: audio ? audio.volume : 0
  readonly property bool muted: audio ? audio.muted : true

  // Percentage is what a reader wants; PipeWire reports a 0.0-1.0 float.
  readonly property int percent: Math.round(volume * 100)

  readonly property string glyph: muted || percent === 0
    ? Util.volumeMute
    : (percent > 66 ? Util.volumeHigh : Util.volumeLow)

  visible: sink !== null

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function adjust(delta) {
    if (!root.audio) return
    const step = delta > 0 ? 0.05 : -0.05
    root.audio.volume = Util.clamp(root.volume + step, 0, 1)
  }

  function toggleMute() {
    if (root.audio) root.audio.muted = !root.audio.muted
  }

  // Tracks the default sink, so unplugging headphones moves the readout to the
  // speakers on its own.
  readonly property var tracked: sink ? [sink] : []

  PwObjectTracker {
    objects: root.tracked
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: root.glyph
    labelText: root.muted ? "MUTE" : root.percent + "%"
    tooltipText: (root.sink ? root.sink.name : "No output")
      + " · scroll to change · click to mute"
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) root.toggleMute()
    }
    onWheelMoved: function (delta) {
      root.adjust(delta)
    }
  }
}