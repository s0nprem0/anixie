import QtQuick
import ".."
import "../Ui"
import Quickshell.Services.Pipewire

// Microphone. Like the volume module this talks to PipeWire directly, so the
// level tracks the stream without polling, and a scroll writes straight back.
// Binding the source to a PwObjectTracker is not optional: an untracked node
// cannot be written to at all.
BarWidget {
  id: root

  readonly property var source: Pipewire.defaultAudioSource
  readonly property var audio: source ? source.audio : null
  readonly property real volume: audio ? audio.volume : 0
  readonly property bool muted: audio ? audio.muted : true

  readonly property int percent: Math.round(volume * 100)
  readonly property bool listening: !muted && percent > 0

  // Hidden on a machine with no capture device rather than left as a dead slot.
  wantsSlot: source !== null
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

  readonly property var tracked: source ? [source] : []

  PwObjectTracker {
    objects: root.tracked
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: root.muted ? Util.micOff : Util.micOn
    // Icon only: a microphone at 100% is noise, and the number is in the tooltip
    labelText: ""
    active: root.listening
    foreground: root.listening ? Theme.danger : Theme.fg
    tooltipText: (root.source ? root.source.name : "No input")
      + (root.muted ? " · muted" : " · " + root.percent + "%")
      + " · scroll to change · left-click to mute · middle-click for the media & audio panel"
    onPressed: function (button) {
      // Mute stays on the primary button; the middle button is the way into the
      // mixer, the same gesture the volume widget uses for its panel.
      if (button === Qt.LeftButton) root.toggleMute()
      else if (button === Qt.MiddleButton) PanelRegistry.toggle("audio", readout)
    }
    onWheelMoved: function (delta) {
      root.adjust(delta)
    }
  }
}