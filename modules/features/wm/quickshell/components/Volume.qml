import QtQuick
import ".."
import "../Ui"
import "../panels"
import Quickshell
import Quickshell.Services.Pipewire

// Volume readout backed by PipeWire directly. The node exposes volume and mute
// as properties that notify on change, so this needs no polling and no wpctl
// subprocess: a scroll on the bar writes straight back to the stream.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click. Registered here because the anchor
  // item and the panel component are both local to this file.
  Component.onCompleted: PanelRegistry.register("audio", readout, mixer)

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null
  readonly property real volume: audio ? audio.volume : 0
  readonly property bool muted: audio ? audio.muted : true

  // Percentage is what a reader wants; PipeWire reports a 0.0-1.0 float.
  readonly property int percent: Math.round(volume * 100)

  readonly property string glyph: muted || percent === 0
    ? Util.volumeMute
    : (percent > 66 ? Util.volumeHigh : Util.volumeLow)

  wantsSlot: sink !== null

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
    // Icon only; the level is in the tooltip and the OSD shows it while it changes.
    labelText: ""
    tooltipText: (root.sink ? root.sink.name : "No output")
      + (root.muted ? " · muted" : " · " + root.percent + "%")
      + " · Super+Ctrl+A · right-click to mute · scroll to change"

    // Declared as an id rather than built inline: `Component { ... }` is an
    // object declaration, so it cannot be passed as a call argument.
    Component {
      id: mixer
      Audio {}
    }

    // Left opens the mixer; mute moves to the right button so clicking the
    // volume is not destructive. Clicking the module again closes it.
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("audio", readout)
      else if (button === Qt.RightButton) root.toggleMute()
    }
    onWheelMoved: function (delta) {
      root.adjust(delta)
    }
  }
}