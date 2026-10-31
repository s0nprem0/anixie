import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

Item {
  id: root

  property int temperature: 4000
  property bool enabled: false
  property bool scheduleEnabled: false
  property string onTime: "19:00"
  property string offTime: "07:00"

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(340)

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

    ToggleSwitch {
      width: card.contentWidth
      label: "Schedule"
      checked: root.scheduleEnabled
      onToggled: function (value) {
        root.scheduleEnabled = value
        root.checkSchedule()
      }
    }

    Row {
      width: card.contentWidth
      spacing: Style.space(6)
      visible: root.scheduleEnabled

      TextField {
        width: (parent.width - Style.space(6)) / 2
        placeholderText: "On (HH:MM)"
        text: root.onTime
        onEditingFinished: root.onTime = text
      }

      TextField {
        width: (parent.width - Style.space(6)) / 2
        placeholderText: "Off (HH:MM)"
        text: root.offTime
        onEditingFinished: root.offTime = text
      }
    }

    PanelSeparator {}

    Flow {
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

  function parseMinutes(t) {
    const parts = String(t || "").split(":")
    if (parts.length !== 2) return -1
    const h = parseInt(parts[0], 10)
    const m = parseInt(parts[1], 10)
    if (!isFinite(h) || !isFinite(m)) return -1
    return h * 60 + m
  }

  function checkSchedule() {
    if (!root.scheduleEnabled) return
    const now = new Date()
    const cur = now.getHours() * 60 + now.getMinutes()
    const on = root.parseMinutes(root.onTime)
    const off = root.parseMinutes(root.offTime)
    if (on < 0 || off < 0) return

    let inRange = false
    if (on < off) inRange = cur >= on && cur < off
    else inRange = cur >= on || cur < off

    if (inRange !== root.enabled) {
      root.enabled = inRange
      root.apply()
    }
  }

  property Timer scheduleTimer: Timer {
    interval: 60000
    running: root.scheduleEnabled
    repeat: true
    onTriggered: root.checkSchedule()
  }

  Component.onCompleted: root.checkSchedule()

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
