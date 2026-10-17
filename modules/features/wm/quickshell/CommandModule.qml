import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "Ui"

// A module backed by a shell command instead of QML. The command may print
// plain text, or Waybar-style JSON for a label plus a state class:
//
//   { "text": "VPN", "tooltip": "Tunnelled", "class": "active" }
//
// "active" tints with the accent, "urgent" and "warning" with the danger
// colour, "inactive" is muted, and anything else takes the normal foreground.
//
// The layout entry drives it, as it does in Omarchy:
//
//   { "id": "vpn", "type": "command", "exec": "vpn-status",
//     "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" }
//
// so a command module can be hovered and clicked like any other.
Item {
  id: root

  property var entry: ({})

  readonly property string command: entry.exec ? String(entry.exec) : ""
  readonly property int intervalMs: entry.interval ? Math.max(1, Number(entry.interval)) * 1000 : 5000

  property string label: ""
  property string cls: ""
  property string tip: ""

  // Non-empty only while the command is failing. Deliberately not shown as a
  // label: a status bar that spells out every transient failure is noisier than
  // one that simply has nothing to show, but the reason still belongs in the
  // tooltip for whoever goes looking.
  property string failure: ""

  // From the layout entry rather than the command's output, so both are known
  // before the first poll returns. "on-click" is accepted alongside "onClick"
  // because that was the spelling in the Waybar config this replaces.
  readonly property string entryTooltip: entry.tooltip ? String(entry.tooltip) : ""
  readonly property string clickCommand: entry.onClick
    ? String(entry.onClick)
    : (entry["on-click"] ? String(entry["on-click"]) : "")

  // A tooltip the command reports beats the static one: it carries live state the
  // layout cannot know, such as a tunnel being up or a build having failed.
  readonly property string tooltipLabel: root.tip !== "" ? root.tip : root.entryTooltip

  // A command with nothing to say collapses rather than leaving a gap.
  // WidgetButton floors an empty label at its horizontal margin, so the width is
  // stated here instead of inherited.
  implicitWidth: root.displayText() === "" ? 0 : button.implicitWidth
  implicitHeight: root.displayText() === "" ? 0 : button.implicitHeight

  function apply(raw) {
    const trimmed = raw.trim()
    if (trimmed === "") return

    if (trimmed.charAt(0) === "{") {
      let parsed = null
      try {
        parsed = JSON.parse(trimmed)
      } catch (e) {
        parsed = null
      }
      if (parsed && typeof parsed === "object") {
        root.label = parsed.text !== undefined ? String(parsed.text) : ""
        root.tip = parsed.tooltip !== undefined ? String(parsed.tooltip) : ""
        root.cls = parsed.class !== undefined ? String(parsed.class) : ""
        return
      }
    }

    root.label = trimmed
    root.cls = ""
  }

  Process {
    id: probe
    running: root.command !== ""
    command: ["sh", "-c", root.command]
    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }

    stderr: StdioCollector {
      // A command that fails explains itself on stderr. Without capturing it the
      // module would just go quiet, which is indistinguishable from a command
      // that succeeded with nothing to say.
      onStreamFinished: root.failure = this.text.trim()
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 && !root.failure) root.failure = "exit " + exitCode
    }
  }

  Timer {
    running: root.command !== ""
    interval: root.intervalMs
    triggeredOnStart: true
    onTriggered: {
      // Optimistic, so a command that recovers stops reporting its last
      // failure without waiting for the run after next.
      root.failure = ""
      probe.running = false
      probe.running = true
    }
  }

  // While a command is failing its stderr stands in for the label it failed to
  // produce, capped so a long stack trace cannot stretch the bar. Shown rather
  // than swallowed: a module that goes quiet is indistinguishable from one that
  // has nothing to report.
  function displayText() {
    if (root.failure !== "") {
      const first = root.failure.split("\n")[0]
      return first.length > 24 ? "…" + first.slice(0, 23) : first
    }

    return root.label
  }

  // A failing command reads as muted rather than urgent: stderr is diagnostic
  // text, not a status the user has to act on.
  function textColor() {
    if (root.failure !== "") return Theme.muted
    if (root.cls === "urgent" || root.cls === "warning") return Theme.danger
    if (root.cls === "active") return Theme.accent
    if (root.cls === "inactive") return Theme.muted
    return Theme.fg
  }

  function click() {
    if (root.clickCommand !== "") Commands.run(root.clickCommand)
  }

  // A WidgetButton rather than a bare Text, so the module takes part in the same
  // hover and tooltip handling as every other button. `active` is off because the
  // colour comes from the command's own class below, not from pressed state.
  WidgetButton {
    id: button
    anchors.centerIn: parent
    active: false
    text: root.displayText()
    foreground: root.textColor()
    fontSize: Style.bar.iconFont
    tooltipText: root.tooltipLabel

    onPressed: function (which) {
      if (which === Qt.LeftButton || which === Qt.MiddleButton) root.click()
    }
  }
}