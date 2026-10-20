import QtQuick
import Quickshell.Io
import ".."
import "../Ui"

// CPU and memory, sampled from /proc. Percentages on the bar, and the figures
// behind them in the panel.
//
// The sample is one process rather than three file watches: /proc/stat is a
// stream of counters, not a value that notifies, and a watch on it either never
// fires or fires for every unrelated line the kernel writes. A two-second
// subprocess is cheaper than pretending it is a property.
BarWidget {
  id: root

  Component.onCompleted: PanelRegistry.register("system", readout, panel)

  readonly property int interval: Math.max(1000, Number(root.setting("interval", 2)) * 1000)

  property bool sampled: false
  property real cpuPercent: 0
  property real memoryPercent: 0
  property real memoryTotal: 0
  property real memoryUsed: 0
  property string load: "—"
  property string uptime: "—"

  // Kept as separate counters between samples: CPU usage is the difference
  // between two readings, not a value /proc/stat prints.
  property real previousTotal: 0
  property real previousIdle: 0

  function formatUptime(seconds) {
    if (!isFinite(seconds) || seconds <= 0) return "—"

    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return (days > 0 ? days + "d " : "") + hours + "h " + minutes + "m"
  }

  function apply(raw) {
    const lines = String(raw).trim().split("\n")
    let total = 0
    let idle = 0
    let memTotal = 0
    let memAvailable = 0
    let loadText = ""
    let uptimeSeconds = 0

    for (let i = 0; i < lines.length; i++) {
      const parts = lines[i].trim().split(/\s+/)

      if (parts[0] === "cpu") {
        total = Number(parts[1])
        idle = Number(parts[2])
      } else if (parts[0] === "mem") {
        memTotal = Number(parts[1])
        memAvailable = Number(parts[2])
      } else if (parts[0] === "load") {
        loadText = parts.slice(1).join(" ")
      } else if (parts[0] === "uptime") {
        uptimeSeconds = Number(parts[1])
      }
    }

    if (root.previousTotal > 0 && total > root.previousTotal) {
      const used = 1 - (idle - root.previousIdle) / (total - root.previousTotal)
      root.cpuPercent = Math.max(0, Math.min(100, used * 100))
    }

    root.previousTotal = total
    root.previousIdle = idle

    if (memTotal > 0) {
      root.memoryTotal = memTotal / 1048576
      root.memoryUsed = (memTotal - memAvailable) / 1048576
      root.memoryPercent = Math.max(0, Math.min(100, (memTotal - memAvailable) * 100 / memTotal))
    }

    root.load = loadText !== "" ? loadText : "—"
    root.uptime = root.formatUptime(uptimeSeconds)
    root.sampled = true
  }

  function refresh() {
    sample.running = false
    sample.running = true
  }

  wantsSlot: root.sampled
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: sample
    running: false

    // CPU: total and idle counters. Memory: total and available in kB. The
    // markers make the output one self-describing stream, so the parser does
    // not have to know which line came from which file.
    command: ["sh", "-c",
      "awk '/^cpu / { total=0; for (i=2;i<=NF;i++) total+=$i; printf \"cpu %s %s\\n\", total, $5+$6 }' /proc/stat; "
      + "awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf \"mem %s %s\\n\", t, a}' /proc/meminfo; "
      + "printf 'load '; cut -d' ' -f1-3 /proc/loadavg; "
      + "printf 'uptime '; cut -d' ' -f1 /proc/uptime"]

    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }
  }

  Timer {
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: readout
    anchors.centerIn: parent
    text: ""
    hasVisualContent: true
    fixedWidth: statsRow.implicitWidth + Style.space(16)
    fixedHeight: Style.bar.sizeHorizontal
    tooltipText: "CPU " + Math.round(root.cpuPercent) + "%"
      + " · Memory " + Math.round(root.memoryPercent) + "%"
      + " (" + root.memoryUsed.toFixed(1) + " / " + root.memoryTotal.toFixed(1) + " GB)"
      + " · click for details"

    Row {
      id: statsRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Util.cpu
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
      }

      Text {
        width: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.cpuPercent) + "%"
        horizontalAlignment: Text.AlignRight
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Util.memory
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
      }

      Text {
        width: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.memoryPercent) + "%"
        horizontalAlignment: Text.AlignRight
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("system")
    }
  }

  Component {
    id: panel

    Panel {
      id: card
      title: "System"

      PanelRow {
        width: card.contentWidth
        label: "CPU"
        value: Math.round(root.cpuPercent) + "%"
      }

      PanelRow {
        width: card.contentWidth
        label: "Memory"
        value: root.memoryUsed.toFixed(1) + " / " + root.memoryTotal.toFixed(1) + " GB"
      }

      PanelRow {
        width: card.contentWidth
        label: "Memory used"
        value: Math.round(root.memoryPercent) + "%"
      }

      PanelRow {
        width: card.contentWidth
        label: "Load average"
        value: root.load
      }

      PanelRow {
        width: card.contentWidth
        label: "Uptime"
        value: root.uptime
      }
    }
  }
}
