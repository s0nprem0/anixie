import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Displays: every output, and what can be changed about it — scale, rotation,
// and whether it is on.
//
// A second screen arrives after the session is built, so this cannot be a file of
// rules written at build time. It asks `monitors list` for what is attached now,
// and applies through the same `monitors set` the keys use, so a change made here
// and one made from a keybind take the same path and land in the same state file.
Item {
  id: root

  // The outputs, as objects. A string until the first read lands, which is what
  // the Repeater falls back to.
  property var outputs: ""

  readonly property bool ready: root.outputs !== ""

  readonly property var scales: [
    { label: "1x", value: "1" },
    { label: "1.25x", value: "1.25" },
    { label: "1.6x", value: "1.6" },
    { label: "2x", value: "2" },
    { label: "3x", value: "3" },
    { label: "4x", value: "4" }
  ]

  // Hyprland numbers rotation; these are the names for them, in the same order.
  readonly property var transforms: [
    { label: "Normal", value: "0" },
    { label: "90°", value: "1" },
    { label: "180°", value: "2" },
    { label: "270°", value: "3" },
    { label: "Flipped", value: "4" },
    { label: "Flipped 90°", value: "5" },
    { label: "Flipped 180°", value: "6" },
    { label: "Flipped 270°", value: "7" }
  ]

  function parse(raw) {
    try {
      const list = JSON.parse(String(raw || ""))
      root.outputs = Array.isArray(list) ? list : []
    } catch (e) {
      root.outputs = []
    }
  }

  function query() {
    listQuery.running = false
    listQuery.running = true
  }

  // A change is optimistic where it can be: the control moves, then the truth is
  // asked for again. Writing optimistically the other way round would leave the
  // panel showing what was asked for if the change was refused.
  function set(output, key, value) {
    Commands.runQuoted("monitors", ["set", output, key, String(value)])
    root.query()
  }

  function indexOf(list, value) {
    for (let i = 0; i < list.length; i++) {
      if (list[i].value === String(value)) return i
    }
    return 0
  }

  Process {
    id: listQuery
    command: ["monitors", "list"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.parse(this.text)
    }
  }

  // Re-read on a timer, because a monitor being plugged in is the one thing here
  // that happens without the panel asking. Slow: a screen arrives rarely, and
  // this is a hyprctl call per tick whatever else it is doing.
  readonly property Timer watch: Timer {
    interval: 8000
    running: true
    repeat: true
    onTriggered: root.query()
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent
    maxWidth: Style.space(340)

    PanelHero {
      width: card.contentWidth
      glyph: Util.sun
      title: "Displays"
      subtitle: root.ready && root.outputs.length > 0
        ? root.outputs.length + (root.outputs.length === 1 ? " screen" : " screens")
        : ""
    }

    PanelSeparator {}

    Text {
      width: card.contentWidth
      visible: !root.ready || root.outputs.length === 0
      height: visible ? implicitHeight : 0
      text: "No screens found"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.ready ? root.outputs : []

      delegate: Item {
        id: block
        required property var modelData
        required property int index

        width: card.contentWidth
        height: body.implicitHeight

        readonly property string name: block.modelData.name
        readonly property bool off: block.modelData.disabled === true

        Column {
          id: body
          width: parent.width
          spacing: Style.space(8)

          // The output's own name, with what it is — a shopper reads "eDP-1" and
          // has to be told that is the laptop panel.
          Text {
            width: parent.width
            text: block.name
                  + (block.modelData.focused ? "  ·  focused" : "")
                  + (block.off ? "  ·  off" : "")
            color: block.off ? Theme.muted : Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: (block.modelData.width || 0) + "×" + (block.modelData.height || 0)
                  + "  ·  " + Math.round(block.modelData.refreshRate || 0) + " Hz"
                  + "  ·  " + (block.modelData.description || "")
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          PanelRow {
            id: scaleRow
            width: parent.width
            hasControl: true
            label: "Scale"
            value: (block.modelData.scale || 1) + "x"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: scaleRow.controlWidth
              model: root.scales
              currentIndex: root.indexOf(root.scales, block.modelData.scale)
              onActivated: function (index) { root.set(block.name, "scale", root.scales[index].value) }
            }
          }

          PanelRow {
            id: rotationRow
            width: parent.width
            hasControl: true
            label: "Rotation"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: rotationRow.controlWidth
              model: root.transforms
              currentIndex: root.indexOf(root.transforms, block.modelData.transform)
              onActivated: function (index) { root.set(block.name, "transform", root.transforms[index].value) }
            }
          }

          Toggle {
            id: power
            width: parent.width
            label: "Screen on"
            checked: !block.off
            description: block.modelData.focused === true ? "the screen you are reading this on" : ""
            // The one screen you are looking at cannot be turned off from a panel
            // that is drawn on it. Everything else can.
            available: block.modelData.focused !== true
            onToggled: root.set(block.name, "disabled", block.off ? "no" : "yes")
          }

          // Between screens. The last row needs no gap under it.
          Item {
            width: 1
            height: block.index === root.outputs.length - 1 ? 0 : Style.space(12)
          }
        }
      }
    }
  }
}