import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

Item {
  id: root

  property int temperature: 4000
  property bool enabled: false

  implicitWidth: Style.space(360)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(360)

    PanelHero {
      width: card.contentWidth
      glyph: Util.moon
      title: "Night light"
      subtitle: root.enabled ? root.temperature + " K" : "Off"
    }

    PanelSeparator {}

    ToggleSwitch {
      width: card.contentWidth
      label: "Enabled"
      checked: root.enabled
      onToggled: function (value) {
        root.enabled = value
        root.apply()
      }
    }

    PanelSeparator {}

    SliderField {
      width: card.contentWidth
      label: "Temperature"
      value: root.temperature + " K"
      from: 1000
      to: 6500
      stepSize: 100
      level: root.temperature
      available: root.enabled
      onMoved: function (value) {
        root.temperature = Math.round(value)
        root.apply()
      }
    }

    PanelSeparator {}

    Row {
      width: card.contentWidth
      spacing: Style.space(6)

      Repeater {
        model: [
          { label: "Candle", value: 1900 },
          { label: "Warm", value: 2700 },
          { label: "Reading", value: 3400 },
          { label: "Neutral", value: 4500 },
          { label: "Daylight", value: 6500 }
        ]

        delegate: TextButton {
          required property var modelData
          label: modelData.label
          active: root.temperature === modelData.value
          available: root.enabled
          onClicked: {
            root.temperature = modelData.value
            root.apply()
          }
        }
      }
    }
  }

  function apply() {
    if (root.enabled) {
      if (CompositorHost.isHyprland) {
        hyprsunset.command = ["hyprsunset", "-t", String(root.temperature)]
        hyprsunset.running = false
        hyprsunset.running = true
      } else {
        gammastep.command = ["gammastep", "-O", String(root.temperature)]
        gammastep.running = false
        gammastep.running = true
      }
    } else {
      if (CompositorHost.isHyprland) {
        hyprsunsetStop.running = false
        hyprsunsetStop.running = true
      } else {
        gammastepStop.running = false
        gammastepStop.running = true
      }
    }
  }

  Process { id: hyprsunset; running: false }
  Process {
    id: hyprsunsetStop
    running: false
    command: ["pkill", "-x", "hyprsunset"]
  }
  Process { id: gammastep; running: false }
  Process {
    id: gammastepStop
    running: false
    command: ["gammastep", "-x"]
  }
}
EOF
echo done