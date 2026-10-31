import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Displays: every output, and what can be changed about it — layout, scale,
// rotation, mode, placement, and whether it is on.
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
  // it would silently ignore a click. A queue does neither. Each entry is
  // { mode: "set" | "try", args: [output, key, value] }.
  property var pending: []

  // The last list this panel rendered. A poll that finds the same answer must
  // not hand the Repeater a new array: that destroys every delegate — and with
  // it an open dropdown and the keyboard ring — once every eight seconds.
  property string snapshot: ""

  // A `monitors try` is in flight, or waiting for Keep/Revert. The dialog owns
  // the screen while this is true and the queue stays parked.
  property bool confirming: false
  property var pendingChange: null
  property string currentMode: ""
  property string action: ""

  readonly property var scales: [
    { label: "1x", value: "1" },
    { label: "1.25x", value: "1.25" },
    { label: "1.5x", value: "1.5" },
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

  readonly property int activeCount: {
    const list = Array.isArray(root.outputs) ? root.outputs : []
    let count = 0
    for (let i = 0; i < list.length; i++) if (list[i].disabled !== true) count += 1
    return count
  }

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
      // A poll that found nothing new must not look like a new list. Assigning
      // it anyway rebuilds every delegate and closes whatever dropdown the
      // pointer is in, which the eight-second fallback would do over and over.
      const next = JSON.stringify(list)
      if (next === root.snapshot) {
        root.listError = ""
        return
      }
      root.snapshot = next
      root.outputs = list
      root.listError = ""
    } catch (e) {
      root.listError = "could not read the display list"
    }
  }

  property bool queryPending: false

  // Hot-plug: re-read the list when an output arrives or leaves, rather than
  // waiting for the next manual refresh or the eight-second fallback.
  property Connections hotplug: Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event && (event.name === "monitoradded" || event.name === "monitorremoved")) {
        root.query()
      }
    }
  }

  function query() {
    // A read already in flight will be followed by one more, rather than being
    // killed and restarted: stopping it would surface as a spurious failure.
    if (listQuery.running) {
      root.queryPending = true
      return
    }
    listQuery.running = true
  }

  // Geometry changes can leave the panel unreadable, so they go through
  // `monitors try` and come back unless Keep is pressed. Mirror and on/off are
  // visible immediately and are undone from the same panel.
  // Placement is offered only as Auto or a position adjacent to another
  // screen, so it cannot strand the output; scale, rotation and mode can.
  function disruptive(key) {
    return key === "scale" || key === "transform" || key === "mode"
  }

  function isOff(name) {
    const list = Array.isArray(root.outputs) ? root.outputs : []
    for (let i = 0; i < list.length; i++) {
      if (list[i].name === name) return list[i].disabled === true
    }
    return false
  }

  function set(output, key, value) {
    if (root.confirming) return
    root.setError = ""
    // An off screen cannot go unreadable, and a try there would revert before
    // anyone turned it back on. Save those changes straight away; they take
    // effect when the screen comes up.
    root.pending.push({
      mode: root.disruptive(key) && !root.isOff(output) ? "try" : "set",
      args: [output, key, String(value)]
    })
    root.startSet()
  }

  function startSet() {
    if (setQuery.running || root.confirming || root.pending.length === 0) return
    const request = root.pending.shift()
    root.currentMode = request.mode
    root.pendingChange = request.mode === "try"
      ? { output: request.args[0], key: request.args[1], value: request.args[2] }
      : null
    setQuery.command = ["monitors", request.mode].concat(request.args)
    setQuery.running = true
  }

  function finishChange(command) {
    if (root.action !== "") return
    root.action = command
    actionQuery.command = ["monitors", command]
    actionQuery.running = true
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

  // ---- modes ----

  function parseMode(value) {
    const match = /^(\d+)x(\d+)@([\d.]+)/.exec(String(value))
    return match
      ? { width: Number(match[1]), height: Number(match[2]), rate: Number(match[3]) }
      : null
  }

  function rateLabel(rate) {
    return String(Math.round(Number(rate) * 100) / 100)
  }

  // Compact enough for the control: the row already says Mode, and a trailing
  // "Hz" is what pushes the rate out of view in the popup.
  function modeLabel(mode) {
    const parsed = root.parseMode(mode)
    return parsed
      ? parsed.width + "×" + parsed.height + " · " + root.rateLabel(parsed.rate)
      : String(mode)
  }

  function modeOptions(block) {
    const modes = (block.availableModes || []).slice()
    const seen = {}
    const parsed = []
    for (let i = 0; i < modes.length; i++) {
      const mode = String(modes[i])
      if (seen[mode]) continue
      seen[mode] = true
      const item = root.parseMode(mode)
      if (item) {
        parsed.push({
          label: root.modeLabel(mode),
          value: mode,
          width: item.width,
          height: item.height,
          rate: item.rate
        })
      }
    }
    // Best first: a mode picker is opened to move to a larger or faster mode,
    // not to scroll past 640×480.
    parsed.sort(function (a, b) {
      return (b.width * b.height - a.width * a.height) || (b.rate - a.rate)
    })
    return [{ label: "Preferred (auto)", value: "preferred" }].concat(parsed)
  }

  // The closest rate at the current resolution, not the first equal integer:
  // 59.94 and 60.00 both round to 60, and the list is not guaranteed to put the
  // one actually in use first.
  function modeIndex(block, modes) {
    if (block.savedMode === "preferred") return 0
    const width = Number(block.width || 0)
    const height = Number(block.height || 0)
    const rate = Number(block.refreshRate || 0)
    let best = -1
    let bestDelta = Infinity
    for (let i = 1; i < modes.length; i++) {
      if (modes[i].width !== width || modes[i].height !== height) continue
      const delta = Math.abs(modes[i].rate - rate)
      if (delta < bestDelta) {
        bestDelta = delta
        best = i
      }
    }
    return bestDelta <= 0.5 ? best : -1
  }

  // ---- names and arrangement ----

  function isInternal(name) {
    return /^(eDP|LVDS|DSI)/.test(String(name))
  }

  function shortName(output) {
    return root.isInternal(output.name) ? "laptop" : String(output.name)
  }

  function displayLabel(block) {
    return root.isInternal(block.name) ? "Laptop panel" : "External display"
  }

  // Hyprland reports width/height in physical pixels but x/y in the layout's
  // logical units. Placement math has to use the same units as x/y, or a
  // 1.25x screen is treated as 1920 wide when the compositor is using 1536.
  function logicalWidth(output) {
    const scale = Number(output.scale || 1)
    return Number(output.width || 0) / (scale > 0 ? scale : 1)
  }

  function logicalHeight(output) {
    const scale = Number(output.scale || 1)
    return Number(output.height || 0) / (scale > 0 ? scale : 1)
  }

  // The other screens this one can be placed against or mirror onto. A screen
  // that is off or already mirroring is not a usable target.
  function otherOutputs(block) {
    const list = Array.isArray(root.outputs) ? root.outputs : []
    const out = []
    for (let i = 0; i < list.length; i++) {
      const other = list[i]
      if (other.name === block.name) continue
      if (other.disabled === true) continue
      if (String(other.mirrorOf || "none") !== "none") continue
      out.push(other)
    }
    return out
  }

  function placementOptions(block) {
    const options = [{ label: "Auto", value: "auto" }]
    const width = root.logicalWidth(block.modelData)
    const height = root.logicalHeight(block.modelData)
    const others = root.otherOutputs(block)
    for (let i = 0; i < others.length; i++) {
      const other = others[i]
      const label = root.shortName(other)
      const otherWidth = root.logicalWidth(other)
      const otherHeight = root.logicalHeight(other)
      options.push({ label: "Left of " + label, value: (other.x - width) + "x" + other.y })
      options.push({ label: "Right of " + label, value: (other.x + otherWidth) + "x" + other.y })
      options.push({ label: "Above " + label, value: other.x + "x" + (other.y - height) })
      options.push({ label: "Below " + label, value: other.x + "x" + (other.y + otherHeight) })
    }
    return options
  }

  function placementIndex(block, options) {
    if (block.modelData.savedPosition === "auto") return 0
    const position = Number(block.modelData.x) + "x" + Number(block.modelData.y)
    for (let i = 1; i < options.length; i++) {
      if (options[i].value === position) return i
    }
    return -1
  }

  function positionLabel(block) {
    const x = Number(block.modelData.x || 0)
    const y = Number(block.modelData.y || 0)
    const width = root.logicalWidth(block.modelData)
    const height = root.logicalHeight(block.modelData)
    const others = root.otherOutputs(block)
    for (let i = 0; i < others.length; i++) {
      const other = others[i]
      const label = root.shortName(other)
      if (other.x + root.logicalWidth(other) === x && other.y === y) return "left of " + label
      if (x + width === other.x && other.y === y) return "right of " + label
      if (other.y + root.logicalHeight(other) === y && other.x === x) return "above " + label
      if (y + height === other.y && other.x === x) return "below " + label
    }
    return x + ", " + y
  }

  function changeDetail() {
    const change = root.pendingChange
    if (!change) return ""

    const labels = { scale: "Scale", transform: "Rotation", mode: "Mode", position: "Placement" }
    let value = String(change.value)
    if (change.key === "transform") {
      const index = Number(change.value)
      if (index >= 0 && index < root.transforms.length) value = root.transforms[index].label
    } else if (change.key === "mode" && value !== "preferred") {
      value = root.modeLabel(value)
    }

    return change.output + " · " + (labels[change.key] || change.key) + ": " + value
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
      const tried = root.currentMode === "try" && code === 0
      root.currentMode = ""

      if (code !== 0) {
        const message = String(setErrorOutput.text || "").trim()
        root.setError = message !== "" ? message : "could not change the display"
        root.pendingChange = null
      }

      // A try that landed is not decided yet: the dialog owns the next step,
      // and the queue stays parked until Keep or Revert has run.
      if (tried) {
        root.confirming = true
        applyDialog.open()
        return
      }

      // The next change starts only after this one has landed, and the panel
      // re-reads only once the queue is empty, so what it shows is the truth
      // rather than the value that was asked for.
      if (root.pending.length > 0) Qt.callLater(function () { root.startSet() })
      else root.query()
    }
  }

  Process {
    id: actionQuery
    stderr: StdioCollector {
      id: actionErrorOutput
    }
    onExited: function (code) {
      if (code !== 0) {
        const message = String(actionErrorOutput.text || "").trim()
        root.setError = message !== "" ? message : "could not settle the display change"
      }

      // Keep and Revert both end the try, including a timer that already fired
      // before the button was pressed.
      root.action = ""
      root.confirming = false
      root.pendingChange = null
      root.query()
      root.startSet()
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
          ? (root.activeCount === root.outputs.length
            ? root.outputs.length + (root.outputs.length === 1 ? " screen" : " screens")
            : root.activeCount + " of " + root.outputs.length + " on")
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

    // The actual arrangement, rather than four absolute numbers per row. It
    // also gives Identify a natural home: the action is about telling these
    // rectangles apart on the desk.
    PanelSectionHeader {
      width: card.contentWidth
      // One screen has nothing to arrange against, and nothing to identify it
      // apart from; the rows below are the whole panel in that case.
      visible: root.ready && root.activeCount > 1
      label: "Arrangement"
      action: "Identify"
      actionEnabled: root.ready && root.activeCount > 1
      onActionTriggered: Commands.run("monitors identify")
    }

    DisplayMap {
      width: card.contentWidth
      outputs: root.ready ? root.outputs : []
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
        readonly property var modes: root.modeOptions(block.modelData)
        readonly property var placements: root.placementOptions(block)

        // A mirror is a layout choice, not a separate mode: the extended
        // layout plus every other screen that could be copied. Built per
        // block because the targets depend on which output this is.
        readonly property var layoutOptions: {
          const options = [{ label: "Extended", value: "none" }]
          const outputs = Array.isArray(root.outputs) ? root.outputs : []
          for (let i = 0; i < outputs.length; i++) {
            const other = outputs[i]
            if (other.name !== block.name && other.disabled !== true
                && String(other.mirrorOf || "none") === "none") {
              options.push({ label: "Mirror of " + root.shortName(other), value: other.name })
            }
          }
          return options
        }

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
          // has to be told that is the laptop panel. The connector stays beside
          // it so the row still matches what `monitors` prints.
          Text {
            width: parent.width
            text: root.displayLabel(block) + "  ·  " + block.name
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
                + "  ·  " + root.rateLabel(block.modelData.refreshRate || 0) + " Hz  ·  ")
              : "")
              + (block.modelData.description || "")
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          // A mirrored output has no geometry of its own to change, so the rows
          // below are disabled rather than silently doing nothing. An output
          // that is off keeps its settings, but they only take effect when it
          // comes back.
          Text {
            width: parent.width
            visible: block.mirroring
            text: "Scale, rotation, mode and placement follow "
              + block.modelData.mirrorOf + " while mirrored."
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            visible: block.off && !block.mirroring
            text: "Changes here apply when this screen is turned on."
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
          }

          // No value beside these: the dropdown says what is chosen, and a
          // second copy of it on the other side of the row is the same fact
          // twice, with a gap between the two halves of it.

          // A single screen has nothing to lay out against, so the row only
          // appears once there is a second attached output to extend onto or
          // mirror. A switched-off output cannot host a mirror either.
          PanelRow {
            id: layoutRow
            width: parent.width
            hasControl: true
            label: "Layout"
            visible: !block.off && block.layoutOptions.length > 1

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: layoutRow.controlWidth
              model: block.layoutOptions
              placeholder: "extended"
              // `monitors list` resolves the target id to its name and
              // normalizes "not mirroring" to none, so an extended screen
              // matches the first option instead of showing a raw id.
              currentIndex: root.indexOf(block.layoutOptions, block.modelData.mirrorOf || "none")
              onActivated: function (index) {
                root.set(block.name, "mirror", block.layoutOptions[index].value)
              }
            }
          }

          PanelRow {
            id: scaleRow
            width: parent.width
            hasControl: true
            label: "Scale"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: scaleRow.controlWidth
              available: !block.mirroring
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
              available: !block.mirroring
              model: root.transforms
              placeholder: "unknown"
              currentIndex: root.indexOf(root.transforms, block.modelData.transform)
              onActivated: function (index) { root.set(block.name, "transform", root.transforms[index].value) }
            }
          }

          PanelRow {
            id: sdrBrightnessRow
            visible: CompositorHost.supportsMonitorColorMgmt
            width: parent.width
            hasControl: true
            label: "SDR brightness"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: sdrBrightnessRow.controlWidth
              model: ["0.8", "1.0", "1.2", "1.5"]
              placeholder: "1.0"
              currentIndex: {
                const v = String(block.modelData.sdrBrightness || "1")
                const idx = ["0.8", "1.0", "1.2", "1.5"].indexOf(v)
                return idx >= 0 ? idx : 1
              }
              onActivated: function (index) {
                root.set(block.name, "sdrbrightness", ["0.8", "1.0", "1.2", "1.5"][index])
              }
            }
          }

          PanelRow {
            id: sdrSaturationRow
            visible: CompositorHost.supportsMonitorColorMgmt
            width: parent.width
            hasControl: true
            label: "SDR saturation"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: sdrSaturationRow.controlWidth
              model: ["0.8", "1.0", "1.2", "1.5"]
              placeholder: "1.0"
              currentIndex: {
                const v = String(block.modelData.sdrSaturation || "1")
                const idx = ["0.8", "1.0", "1.2", "1.5"].indexOf(v)
                return idx >= 0 ? idx : 1
              }
              onActivated: function (index) {
                root.set(block.name, "sdrsaturation", ["0.8", "1.0", "1.2", "1.5"][index])
              }
            }
          }

          PanelRow {
            id: colorMgmtRow
            width: parent.width
            hasControl: false
            label: "Color management"

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: String(block.modelData.colorManagementPreset || "—")
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
            }
          }

          PanelRow {
            id: modeRow
            width: parent.width
            hasControl: true
            label: "Mode"
            // A resolution and its rate are wider than the standard 140px slot,
            // and "1280×1024 · 60.01" was losing the rate it exists to show.
            controlWidth: Style.space(200)

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: modeRow.controlWidth
              available: !block.mirroring
              model: block.modes
              placeholder: (block.modelData.width || 0) > 0
                ? root.modeLabel(block.modelData.width + "x" + block.modelData.height
                  + "@" + block.modelData.refreshRate)
                : "unknown"
              currentIndex: root.modeIndex(block.modelData, block.modes)
              onActivated: function (index) {
                root.set(block.name, "mode", String(block.modes[index].value))
              }
            }
          }

          PanelRow {
            id: positionRow
            width: parent.width
            hasControl: true
            label: "Placement"

            Dropdown {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: positionRow.controlWidth
              available: !block.mirroring
              model: block.placements
              placeholder: root.positionLabel(block)
              currentIndex: root.placementIndex(block, block.placements)
              onActivated: function (index) {
                root.set(block.name, "position", block.placements[index].value)
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

  // Outside the card, not inside it: a Panel's children go into its content
  // column, and a dialog laid out as a row would be zero-sized. A scale,
  // rotation or mode change keeps its countdown here even if it makes the
  // screen hard to read; the script's own timer is the backstop when this whole
  // panel goes away.
  ConfirmDialog {
    id: applyDialog
    anchors.fill: parent
    // Keep in step with `revert_seconds` in modules/features/wm/display/monitors.sh.
    countdown: 15
    text: "Keep this display setting?"
    detail: root.changeDetail()
    confirmText: "Keep"
    cancelText: "Revert"
    onConfirmed: root.finishChange("keep")
    onCancelled: root.finishChange("revert")
    onTimedOut: root.finishChange("revert")
  }
}