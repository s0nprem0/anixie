import QtQuick
import Quickshell.Io
import ".."
import "../Ui"

// CPU and memory, sampled from /proc. Percentages on the bar, and the figures
// behind them in the panel.
//
// Reading the files directly is what makes this cheap: the first version ran
// `sh` with two `awk`s and two `cut`s every two seconds, which is four forks for
// four lines of text. The files are reloaded on a timer rather than watched —
// /proc/stat is a stream of counters, not a value that notifies, and a watch
// either never fires or fires for every unrelated line the kernel writes.
BarWidget {
  id: root

  Component.onCompleted: root.registerPanel("system", readout, panel)

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

  // /proc/stat's first line is `cpu user nice system idle iowait irq softirq
  // steal ...`. The total is every field after the label, and idle is idle plus
  // iowait, the same figures the old awk used.
  function applyStat(raw) {
    const parts = String(raw).split("\n")[0].trim().split(/\s+/)
    if (parts[0] !== "cpu") return

    let total = 0
    for (let i = 1; i < parts.length; i++) total += Number(parts[i]) || 0
    const idle = (Number(parts[4]) || 0) + (Number(parts[5]) || 0)

    if (root.previousTotal > 0 && total > root.previousTotal) {
      const used = 1 - (idle - root.previousIdle) / (total - root.previousTotal)
      root.cpuPercent = Math.max(0, Math.min(100, used * 100))
    }

    root.previousTotal = total
    root.previousIdle = idle
    root.sampled = true
  }

  function applyMemory(raw) {
    const lines = String(raw).split("\n")
    let memTotal = 0
    let memAvailable = 0

    for (let i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("MemTotal:") === 0) memTotal = Number(lines[i].split(/\s+/)[1]) || 0
      else if (lines[i].indexOf("MemAvailable:") === 0) {
        memAvailable = Number(lines[i].split(/\s+/)[1]) || 0
      }
    }

    if (memTotal > 0) {
      root.memoryTotal = memTotal / 1048576
      root.memoryUsed = (memTotal - memAvailable) / 1048576
      root.memoryPercent = Math.max(0, Math.min(100, (memTotal - memAvailable) * 100 / memTotal))
    }
  }

  function applyLoad(raw) {
    const parts = String(raw).trim().split(/\s+/)
    if (parts.length >= 3) root.load = parts.slice(0, 3).join(" ")
  }

  function applyUptime(raw) {
    const seconds = Number(String(raw).trim().split(/\s+/)[0])
    if (isFinite(seconds)) root.uptime = root.formatUptime(seconds)
  }

  function refresh() {
    statFile.reload()
    memoryFile.reload()
    loadFile.reload()
    uptimeFile.reload()
  }

  wantsSlot: root.sampled
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  FileView {
    id: statFile
    path: "/proc/stat"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyStat(statFile.text())
  }

  FileView {
    id: memoryFile
    path: "/proc/meminfo"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyMemory(memoryFile.text())
  }

  FileView {
    id: loadFile
    path: "/proc/loadavg"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyLoad(loadFile.text())
  }

  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyUptime(uptimeFile.text())
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
    contextMenu: [
      { label: "System panel", glyph: Util.cpu, action: function () { PanelRegistry.toggle("system", readout) } }
    ]
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
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("system", readout)
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
