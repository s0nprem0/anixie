import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Services.Pipewire

// Audio panel. Everything here reads straight off PipeWire: the node list is
// change-notifying, so plugging in headphones moves the default sink and its
// row without anything polling.
Item {
  id: root

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink

  // Sinks are what you can play *to*; streams are what is playing *now*.
  readonly property var sinks: {
    const out = []
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i] && nodes[i].isSink && nodes[i].audio) out.push(nodes[i])
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

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    title: "Audio"

    // ---- master ----
    PanelRow {
      id: masterRow
      width: card.contentWidth
      label: "Volume"
      value: root.defaultSink && root.defaultSink.audio
        ? Math.round(root.defaultSink.audio.volume * 100) + "%"
        : "—"

      Slider {
        id: master
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: masterRow.controlWidth
        from: 0
        to: 1
        stepSize: 0.02
        enabled: root.defaultSink !== null
        value: root.defaultSink && root.defaultSink.audio ? root.defaultSink.audio.volume : 0
        onMoved: if (root.defaultSink && root.defaultSink.audio) root.defaultSink.audio.volume = value
      }
    }

    // ---- outputs ----
    Text {
      width: card.contentWidth
      visible: root.sinks.length > 1
      text: "OUTPUT"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      height: implicitHeight
      topPadding: Style.space(4)
    }

    Repeater {
      model: root.sinks

      delegate: PanelRow {
        required property var modelData
        width: card.contentWidth
        label: root.displayName(modelData)

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 8
          height: 8
          radius: 4
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

    // ---- per-app mixer ----
    Text {
      width: card.contentWidth
      visible: root.streams.length > 0
      text: "PLAYING"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      height: implicitHeight
      topPadding: Style.space(4)
    }

    Repeater {
      model: root.streams

      delegate: PanelRow {
        id: streamRow
        required property var modelData
        width: card.contentWidth
        label: root.displayName(modelData)
        value: Math.round(modelData.audio.volume * 100) + "%"

        Slider {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: streamRow.controlWidth
          from: 0
          to: 1
          stepSize: 0.02
          value: streamRow.modelData.audio.volume
          onMoved: streamRow.modelData.audio.volume = value
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