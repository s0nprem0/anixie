import QtQuick
import ".."
import Quickshell
import Quickshell.Io

Text {
  id: root
  color: {
    if (level < 0)
      return Theme.muted
    if (level <= 15 && !charging)
      return Theme.danger
    if (charging)
      return Theme.success
    return Theme.fg
  }
  font.family: "JetBrains Mono"
  font.pixelSize: 13

  property int level: -1
  property bool charging: false

  readonly property string capPath: "/sys/class/power_supply/BAT0/capacity"
  readonly property string statusPath: "/sys/class/power_supply/BAT0/status"

  Process {
    id: capProc
    running: true
    command: ["cat", capPath]
    stdout: StdioCollector {
      onStreamFinished: {
        const v = parseInt(this.text.trim(), 10)
        if (!isNaN(v))
          root.level = v
      }
    }
  }

  Process {
    id: statusProc
    running: capProc.running
    command: ["cat", statusPath]
    stdout: StdioCollector {
      onStreamFinished: root.charging = this.text.trim() === "Charging"
    }
  }

  // Refresh every 60s so the percentage tracks discharge without polling hard.
  // Both processes are restarted: statusProc only ever follows capProc.running,
  // so without an explicit toggle it would keep its first reading forever.
  Timer {
    running: true
    interval: 60000
    triggeredOnStart: true
    onTriggered: {
      capProc.running = false; capProc.running = true
      statusProc.running = false; statusProc.running = true
    }
  }

  text: level < 0 ? "" : ("BAT " + level + "%" + (charging ? " +" : ""))
}