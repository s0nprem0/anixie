import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Pipewire

// Audio panel: what you are playing to, what you are recording from, and what
// each application is doing on its own.
//
// Everything here reads straight off PipeWire: the node list is change-
// notifying, so plugging in headphones moves the default sink and its row
// without anything polling.
//
// Levels are set with SliderField rather than a control in the right of a
// labelled row: a full-width slider is easier to hit and easier to read, and it
// leaves the number somewhere it can actually be seen — in the header, with
// room — instead of fighting the handle for the same few pixels.
Item {
  id: root

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property var sinkAudio: root.defaultSink ? root.defaultSink.audio : null
  readonly property var sourceAudio: root.defaultSource ? root.defaultSource.audio : null

  readonly property int outputPercent: root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) : 0
  readonly property bool outputMuted: root.sinkAudio ? root.sinkAudio.muted : true
  readonly property bool outputReady: root.sinkAudio !== null

  readonly property int inputPercent: root.sourceAudio ? Math.round(root.sourceAudio.volume * 100) : 0
  readonly property bool inputMuted: root.sourceAudio ? root.sourceAudio.muted : true

  // Sinks are what you can play *to*; streams are what is playing *now*.
  //
  // `!isStream` matters: a playback stream reports `isSink` as well — it is
  // something audio is routed into — so without it every playing application
  // turned up in the output-device list as though it were a pair of headphones,
  // which is what put "Firefox" in the list of things you could switch to.
  readonly property var sinks: {
    const out = []
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i] && nodes[i].isSink && !nodes[i].isStream && nodes[i].audio) out.push(nodes[i])
    }
    return out
  }

  readonly property var streams: {
    const out = []
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i] && nodes[i].isStream && nodes[i].audio) out.push(nodes[i])
    }
    return out
  }

  // The device list is only worth a section when there is a choice to make: one
  // output is not a list, and a row naming the thing the hero already named is
  // noise.
  readonly property bool multipleSinks: root.sinks.length > 1

  // Names carry a device suffix that means nothing in a menu.
  function displayName(node) {
    return String(node.description || node.name || "")
  }

  // The hero's glyph follows the level rather than the node, so muting reads at
  // a glance without reading the number.
  function outputIcon() {
    if (root.outputMuted || root.outputPercent === 0) return Util.volumeMute
    return root.outputPercent > 66 ? Util.volumeHigh : Util.volumeLow
  }

  function inputIcon() {
    if (root.inputMuted || root.inputPercent === 0) return Util.micOff
    return Util.micOn
  }

  function level(node) {
    return node && node.audio ? node.audio.volume : 0
  }

  function percent(node) {
    return node && node.audio ? Math.round(node.audio.volume * 100) : 0
  }

  function setLevel(node, value) {
    if (node && node.audio) node.audio.volume = value
  }

  function setMuted(node, muted) {
    if (node && node.audio) node.audio.muted = muted
  }

  // Selecting an output is two things: tell WirePlumber what the default is, and
  // move what is already playing, which a new default does not do on its own.
  // The command carries both identifiers because the two layers name a sink
  // differently — node id for PipeWire, sink name for the PulseAudio
  // compatibility layer that does the moving.
  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached(["audio-output-set", String(node.id), String(node.name)])
    }
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- the hero ----
    //
    // The output's name and the switch that mutes everything. This is the one
    // control on the panel worth reaching for without aiming, so it sits at the
    // top where it can be hit from the glyph the module was clicked by. The
    // level itself is stated in the Output header below rather than here: it is
    // said once, next to the slider that sets it, instead of twice.
    PanelHero {
      width: card.contentWidth
      glyph: root.outputIcon()
      title: "Audio"
      subtitle: !root.outputReady
        ? "no output device"
        : root.displayName(root.defaultSink)
      controlWidth: powerSwitch.implicitWidth

      // The glyph is dimmed rather than swapped: it keeps saying *which* output
      // this is, and the dimming says it is not currently heard.
      ToggleSwitch {
        id: powerSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.outputReady
        opacity: root.outputReady ? 1 : Style.disabledOpacity
        checked: !root.outputMuted
        onToggled: root.setMuted(root.defaultSink, !root.outputMuted)
      }
    }

    PanelSeparator {}

    // ---- output ----
    //
    // The level is stated in the header and set below it. The header is where the
    // number has room; the slider is where the hand goes.
    SliderField {
      width: card.contentWidth
      label: "Output"
      value: !root.outputReady ? "—" : (root.outputMuted ? "muted" : root.outputPercent + "%")
      from: 0
      to: 1
      stepSize: 0.02
      level: root.level(root.defaultSink)
      available: root.outputReady
      onMoved: function (value) { root.setLevel(root.defaultSink, value) }
    }

    // The device list, and only when there is a choice to make.
    Repeater {
      model: root.multipleSinks ? root.sinks : []

      delegate: ChoiceRow {
        required property var modelData

        width: card.contentWidth
        label: root.displayName(modelData)
        selected: root.defaultSink === modelData
        onClicked: root.setDefaultSink(modelData)
      }
    }

    // ---- input ----
    SliderField {
      width: card.contentWidth
      label: "Input"
      value: root.defaultSource === null ? "none" : (root.inputMuted ? "muted" : root.inputPercent + "%")
      from: 0
      to: 1
      stepSize: 0.02
      level: root.level(root.defaultSource)
      available: root.defaultSource !== null
      onMoved: function (value) { root.setLevel(root.defaultSource, value) }
    }

    // ---- per-application ----
    //
    // The same shape as the two above, once per application: name and level on
    // one line, a slider under it. A mixer row is the one place a second line
    // earns its keep, because the name is what tells you which of six identical
    // sliders you are looking at.
    //
    // "Applications", not "Playing now": this is a mixer, and what is playing —
    // the track, the artist, the transport — is the media widget's popup. Calling
    // both of them now-playing made two different things look like the same one.
    PanelSeparator {
      visible: root.streams.length > 0
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.streams.length > 0
      label: "Applications"
    }

    Repeater {
      model: root.streams

      delegate: SliderField {
        id: streamField
        required property var modelData

        width: card.contentWidth
        // Named by the stream itself, so the header says the application rather
        // than a heading repeated above every row.
        label: root.displayName(modelData)
        value: root.percent(modelData) + "%"
        from: 0
        to: 1
        stepSize: 0.02
        level: root.level(modelData)
        onMoved: function (value) { root.setLevel(modelData, value) }
      }
    }
  }

  // Keep the nodes alive: without tracking, their volumes cannot be written.
  PwObjectTracker {
    objects: {
      const keep = []
      for (let i = 0; i < root.sinks.length; i++) keep.push(root.sinks[i])
      for (let i = 0; i < root.streams.length; i++) keep.push(root.streams[i])
      return keep
    }
  }
}