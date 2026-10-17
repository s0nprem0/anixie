import QtQuick
import Quickshell
import Quickshell.Io
import "."

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
  }

  Timer {
    running: root.command !== ""
    interval: root.intervalMs
    triggeredOnStart: true
    onTriggered: {
      probe.running = false
      probe.running = true
    }
  }

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    font.family: "JetBrains Mono"
    font.pixelSize: 13
    color: {
      if (root.cls === "urgent" || root.cls === "warning") return Theme.danger
      if (root.cls === "active") return Theme.accent
      if (root.cls === "inactive") return Theme.muted
      return Theme.fg
    }
  }
}