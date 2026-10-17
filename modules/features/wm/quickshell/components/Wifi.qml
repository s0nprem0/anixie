import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Wifi readout. Uses nmcli because nixpkgs ships no NetworkManager connection
// editor, so this is also the only place wifi state gets surfaced.
BarWidget {
  id: root

  property bool connected: false
  property string ssid: ""
  property int signal: 0

  readonly property bool resolved: connected && ssid !== ""

  // Hidden rather than showing "offline": a bar that reflows every time the
  // network drops is noisier than one that simply loses a module.
  visible: resolved

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: probe
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "device", "wifi", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        let label = ""
        const rows = this.text.split("\n")

        for (let i = 0; i < rows.length; i++) {
          const parts = rows[i].split(":")

          // nmcli escapes a colon inside an SSID as "\:"; rejoin everything
          // between the first field and the last so those SSIDs read right.
          if (parts[0] === "*") {
            label = parts.slice(1, parts.length - 1).join(":") + " " + parts[parts.length - 1] + "%"
            break
          }
        }

        root.connected = label !== ""
        root.ssid = label
      }
    }
  }

  Timer {
    running: true
    interval: 10000
    triggeredOnStart: true
    onTriggered: {
      probe.running = false
      probe.running = true
    }
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.wifi
    labelText: root.ssid
    tooltipText: root.resolved ? root.ssid : "Wi-Fi off"
    onPressed: function (button) {
      if (button === Qt.LeftButton) root.openSettings()
    }
  }

  function openSettings() {
    openProc.command = ["nm-connection-editor"]
    openProc.running = true
  }

  Process {
    id: openProc
    running: false
  }
}