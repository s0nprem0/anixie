import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Pipewire

// Audio panel: what you are playing to, what you are recording from, and what
// each application is doing on its own.
//
// The shape follows the reference's: a hero that says what the output is and
// carries the one switch worth reaching for — everything, or nothing — then a
// section per level, each with its number in the header and a slider that spans
// the panel.
//
// Full-width sliders rather than a control crammed into the right of a labelled
// row. A slider three-quarters of the width is easier to hit and easier to read,
// and it leaves the number somewhere it can actually be seen: in the header,
// with room, instead of fighting the handle for the same few pixels.
//
// Everything here reads straight off PipeWire: the node list is change-
// notifying, so plugging in headphones moves the default sink and its row
// without anything polling.
Item {
  id: root

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property var sinkAudio: root.defaultSink ? root.defaultSink.audio : null
  readonly property var sourceAudio: root.defaultSource ? root.defaultSource.audio : null

  readonly property int outputPercent: root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) : 0
  readonly property bool outputMuted: root.sinkAudio ? root.sinkAudio.muted : true

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

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    title: "Audio"

    // ---- the hero ----
    //
    // The output's name and level, and the switch that mutes everything. This is
    // the one control on the panel worth reaching for without aiming, so it sits
    // at the top where it can be hit from the glyph you already clicked.
    Item {
      width: card.contentWidth
      height: Style.space(30)

      Text {
        id: heroIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.outputIcon()
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        // Dimmed rather than swapped: the glyph keeps saying *which* output, and
        // the dimming says it is not currently heard.
        opacity: root.outputMuted ? 0.5 : 1
        renderType: Text.NativeRendering
      }

      Column {
        anchors.left: heroIcon.right
        anchors.leftMargin: Style.space(12)
        anchors.right: powerSwitch.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.defaultSink ? root.displayName(root.defaultSink) : "No output"
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: root.outputMuted ? "MUTED" : root.outputPercent + "%"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
      }

      ToggleSwitch {
        id: powerSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: !root.outputMuted
        onToggled: if (root.sinkAudio) root.sinkAudio.muted = !root.sinkAudio.muted
      }
    }

    PanelSeparator {}

    // ---- output ----
    //
    // The level is stated in the header and set below it. The header is where the
    // number has room; the slider is where the hand goes, and it can have the
    // whole width because nothing is competing with it for the end of the row.
    Item {
      width: card.contentWidth
      height: outputHeader.implicitHeight

      PanelSectionHeader {
        id: outputHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        label: "Output"
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.outputMuted ? "muted" : root.outputPercent + "%"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
      }
    }

    Slider {
      id: outputSlider
      width: card.contentWidth
      from: 0
      to: 1
      stepSize: 0.02
      enabled: root.sinkAudio !== null
      value: root.sinkAudio ? root.sinkAudio.volume : 0
      onMoved: if (root.sinkAudio) root.sinkAudio.volume = value
    }

    // The device list, and only when there is a choice to make: one output is not
    // a list, and a row naming the thing already named in the hero is noise.
    Repeater {
      model: root.sinks.length > 1 ? root.sinks : []

      delegate: PanelRow {
        required property var modelData
        width: card.contentWidth
        label: root.displayName(modelData)

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 8
          height: 8
          radius: Theme.cornerRadius
          color: root.defaultSink === modelData ? Theme.primary : Theme.muted

          MouseArea {
            anchors.fill: parent
            anchors.margins: -10
            cursorShape: Qt.PointingHandCursor
            onClicked: Pipewire.defaultAudioSink = modelData
          }
        }
      }
    }

    PanelSeparator {}

    // ---- input ----
    Item {
      width: card.contentWidth
      height: inputHeader.implicitHeight

      PanelSectionHeader {
        id: inputHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        label: "Input"
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.defaultSource === null
          ? "none"
          : (root.inputMuted ? "muted" : root.inputPercent + "%")
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
      }
    }

    Slider {
      id: inputSlider
      width: card.contentWidth
      from: 0
      to: 1
      stepSize: 0.02
      enabled: root.sourceAudio !== null
      value: root.sourceAudio ? root.sourceAudio.volume : 0
      onMoved: if (root.sourceAudio) root.sourceAudio.volume = value
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

      delegate: Column {
        id: streamBlock
        required property var modelData

        width: card.contentWidth
        spacing: Style.space(4)

        Item {
          width: parent.width
          height: Math.max(streamName.implicitHeight, streamPercent.implicitHeight)

          Text {
            id: streamName
            anchors.left: parent.left
            anchors.right: streamPercent.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayName(streamBlock.modelData)
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          Text {
            id: streamPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(streamBlock.modelData.audio.volume * 100) + "%"
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
          }
        }

        Slider {
          width: parent.width
          from: 0
          to: 1
          stepSize: 0.02
          value: streamBlock.modelData.audio.volume
          onMoved: streamBlock.modelData.audio.volume = value
        }
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
