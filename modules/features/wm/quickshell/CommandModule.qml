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

  implicitWidth: text.implicitWidth
  implicitHeight: text.implicitHeight

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

  Text {
    id: text
    anchors.centerIn: parent
    text: root.displayText()
    font.family: Style.font.family
    font.pixelSize: 13
    color: root.textColor()
  }
}