import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Hyprland
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

  // A failed read leaves the last good list in place, and a failed write is
  // reported rather than swallowed; `error` is whichever happened most recently.
  property string listError: ""
  property string setError: ""
  readonly property string error: root.setError !== "" ? root.setError : root.listError

  // Changes are applied one at a time, in order. Starting a second `monitors
  // set` while the first is still running would race the two writes; dropping
  // it would silently ignore a click. A queue does neither.
  property var pending: []

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

  // Relative placement, the part of arrangement that does not need a drag
  // canvas. Arbitrary XxY stays available through `monitors set position`.
  readonly property var positions: [
    { label: "Auto", value: "auto" },
    { label: "Left of others", value: "auto-left" },
    { label: "Right of others", value: "auto-right" },
    { label: "Above others", value: "auto-up" },
    { label: "Below others", value: "auto-down" }
  ]

  function parse(raw) {
    const text = String(raw || "").trim()
    // An empty read is a failure, not an empty desktop: keep the last list
    // rather than blanking the panel on a transient hyprctl error.
    if (text === "") return

    try {
      const list = JSON.parse(text)
      if (!Array.isArray(list)) {
        root.listError = "could not read the display list"
        return
      }
      root.outputs = list
      root.listError = ""
    } catch (e) {
      root.listError = "could not read the display list"
    }
  }

  property bool queryPending: false

  function query() {
    // A read already in flight will be followed by one more, rather than being
    // killed and restarted: stopping it would surface as a spurious failure.
    if (listQuery.running) {
      root.queryPending = true
      return
    }
    listQuery.running = true
  }

  function set(output, key, value) {
    root.setError = ""
    root.pending.push([output, key, String(value)])
    root.startSet()
  }

  function startSet() {
    if (setQuery.running || root.pending.length === 0) return
    const args = root.pending.shift()
    setQuery.command = ["monitors", "set"].concat(args)
    setQuery.running = true
  }

  // -1 when the current value is not one of the offered ones, rather than 0 —
  // falling back to the first entry showed "1x" on a screen set to something
  // else, which is a panel telling you the wrong thing in order to have
  // something to draw.
  function indexOf(list, value) {
    for (let i = 0; i < list.length; i++) {
      if (list[i].value === String(value)) return i
    }
    return -1
  }

  // Match the current pixel size and rounded refresh rate against Hyprland's
  // mode strings, which carry more decimals than the panel needs to show.
  function modeIndex(modes, block) {
    const width = Number(block.width || 0)
    const height = Number(block.height || 0)
    const refresh = Math.round(Number(block.refreshRate || 0))
    for (let i = 0; i < modes.length; i++) {
      const match = /^(\d+)x(\d+)@([\d.]+)/.exec(String(modes[i]))
      if (match && Number(match[1]) === width && Number(match[2]) === height
          && Math.round(Number(match[3])) === refresh) return i
    }
    return -1
  }

  Process {
    id: listQuery
    command: ["monitors", "list"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.parse(this.text)
    }
    stderr: StdioCollector {
      id: listErrorOutput
    }
    onExited: function (code) {
      if (code !== 0) {
        const message = String(listErrorOutput.text || "").trim()
        root.listError = message !== "" ? message : "could not read the display list"
      }
      if (root.queryPending) {
        root.queryPending = false
        root.query()
      }
    }
  }

  Process {
    id: setQuery
    stderr: StdioCollector {
      id: setErrorOutput
    }
    onExited: function (code) {
      if (code !== 0) {
        const message = String(setErrorOutput.text || "").trim()
        root.setError = message !== "" ? message : "could not change the display"
      }

      // The next change starts only after this one has landed, and the panel
      // re-reads only once the queue is empty, so what it shows is the truth
      // rather than the value that was asked for.
      if (root.pending.length > 0) Qt.callLater(function () { root.startSet() })
      else root.query()
    }
  }

  // The timer is a backstop for a screen arriving while the panel is open. The
  // event makes the common case immediate; the timer covers anything Hyprland
  // does not announce.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "monitoradded" || event.name === "monitoraddedv2"
          || event.name === "monitorremoved" || event.name === "monitorremovedv2") {
        root.query()
      }
    }
  }

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

    PanelHero {
      width: card.contentWidth
      glyph: Util.sun
      title: "Displays"
      subtitle: !root.ready
        ? "reading…"
        : (root.outputs.length > 0
          ? root.outputs.length + (root.outputs.length === 1 ? " screen" : " screens")
          : "none found")
    }

    Text {
      width: card.contentWidth
      visible: root.error !== ""
      height: implicitHeight
      text: root.error
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      renderType: Text.NativeRendering
    }

    PanelSeparator {
      visible: root.ready && root.outputs.length > 0
    }

    Text {
      width: card.contentWidth
      visible: !root.ready || root.outputs.length === 0
      height: implicitHeight
      text: root.ready ? "No screens found" : "Looking for screens…"
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
        readonly property bool focused: block.modelData.focused === true
        readonly property bool mirroring: String(block.modelData.mirrorOf || "none") !== "none"

        // Between screens. The last one needs no gap under it, and a rule is
        // clearer than space for a list of separate objects.
        PanelSeparator {
          anchors.top: parent.top
          visible: block.index > 0
        }

        Column {
          id: body
          anchors.top: parent.top
          anchors.topMargin: block.index > 0 ? Style.space(12) : 0
          width: parent.width
          spacing: Style.space(8)

          // The output's own name, with what it is — a shopper reads "eDP-1" and
          // has to be told that is the laptop panel.
          Text {
            width: parent.width
            text: block.name
                  + (block.mirroring ? "  ·  mirrors " + block.modelData.mirrorOf : "")
                  + (block.focused ? "  ·  focused" : "")
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
            // A disabled output can come back with no mode, which is not a
            // useful thing to print as "0×0 · 0 Hz". The description still is.
            text: ((block.modelData.width || 0) > 0
              ? (block.modelData.width + "×" + block.modelData.height
                + "  ·  " + Math.round(block.modelData.refreshRate || 0) + " Hz  ·  ")
              : "")
              + (block.modelData.description || "")
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          // No value beside these: the dropdown says what is chosen, and a
          // second copy of it on the other side of the row is the same fact
          // twice, with a gap between the two halves of it.
          PanelRow {
            id: scaleRow
            width: parent.width
            hasControl: true
            label: "Scale"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: scaleRow.controlWidth
              model: root.scales
              placeholder: "unknown"
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
              placeholder: "unknown"
              currentIndex: root.indexOf(root.transforms, block.modelData.transform)
              onActivated: function (index) { root.set(block.name, "transform", root.transforms[index].value) }
            }
          }

          PanelRow {
            id: modeRow
            width: parent.width
            hasControl: true
            label: "Mode"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: modeRow.controlWidth
              model: block.modelData.availableModes || []
              placeholder: (block.modelData.width || 0) > 0
                ? block.modelData.width + "×" + block.modelData.height
                  + "@" + Math.round(block.modelData.refreshRate || 0)
                : "unknown"
              currentIndex: root.modeIndex(block.modelData.availableModes || [], block.modelData)
              onActivated: function (index) {
                root.set(block.name, "mode", String(block.modelData.availableModes[index]))
              }
            }
          }

          PanelRow {
            id: positionRow
            width: parent.width
            hasControl: true
            label: "Position"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: positionRow.controlWidth
              model: root.positions
              placeholder: block.modelData.x + "," + block.modelData.y
              currentIndex: -1
              onActivated: function (index) {
                root.set(block.name, "position", root.positions[index].value)
              }
            }
          }

          Toggle {
            id: power
            width: parent.width
            label: "Screen on"
            checked: !block.off
            // The one screen you are looking at cannot be turned off from a panel
            // that is drawn on it. Everything else can, and says so rather than
            // offering a switch that quietly does nothing.
            available: !block.focused
            description: block.focused ? "this is the screen you are reading on" : ""
            onToggled: root.set(block.name, "disabled", block.off ? "no" : "yes")
          }
        }
      }
    }
  }
}