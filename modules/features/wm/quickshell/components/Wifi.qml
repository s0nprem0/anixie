import QtQuick
import ".."
import Quickshell
import Quickshell.Io

// Wifi block. Uses nmcli because nixpkgs ships no NetworkManager connection
// editor, so this is also the only place wifi state gets surfaced.
Text {
  id: root
  color: connected ? Theme.fg : Theme.muted
  font.family: "JetBrains Mono"
  font.pixelSize: 13

  property var entry: ({})

  property bool connected: false
  property string ssid: ""
  property int signal: 0

  Process {
    id: probe
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "device", "wifi", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        let found = false
        let label = ""
        const rows = this.text.split("\n")
        for (let i = 0; i < rows.length; i++) {
          const parts = rows[i].split(":")
          // nmcli escapes a colon inside an SSID as "\:"; rejoin everything
          // between the first field and the last so those SSIDs read right.
          if (parts[0] === "*") {
            found = true
            label = parts.slice(1, parts.length - 1).join(":") + " " + parts[parts.length - 1] + "%"
            break
          }
        }
        root.connected = found
        root.ssid = label
      }
    }
  }

  Timer {
    running: true
    interval: 10000
    triggeredOnStart: true
    onTriggered: { probe.running = false; probe.running = true }
  }

  text: connected ? ssid : "WIFI OFF"
}
