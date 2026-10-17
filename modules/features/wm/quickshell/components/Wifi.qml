import QtQuick
import ".."
import "../Ui"
import "../panels"
import Quickshell
import Quickshell.Io

// Wifi readout. Uses nmcli because nixpkgs ships no NetworkManager connection
// editor, so this is also the only place wifi state gets surfaced.
//
// nmcli is a subprocess rather than a native API, so a failure and an empty
// result both arrive as "no output". Those are different facts and the module
// keeps them apart: `failed` means the query itself did not work, which is
// worth showing, while merely having no network is not.
BarWidget {
  id: root

  property bool connected: false
  property string ssid: ""
  property int signal: 0

  // nmcli could not be run, or exited non-zero. Distinct from being offline.
  property bool failed: false

  // A run that comes back with no output can be the first one of a session,
  // where the process loses its output as the shell finishes starting. Two
  // retries is enough to tell that apart from a genuinely quiet radio.
  property int emptyRuns: 0

  readonly property bool resolved: connected && ssid !== ""

  // Offline hides the module, since a bar that reflows every time the network
  // drops is noisier than one that simply loses a module. A failed query shows,
  // because a missing icon would otherwise read as "no network" and hide a
  // broken backend.
  visible: resolved || failed

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function parse(raw) {
    const rows = String(raw).split("\n")

    for (let i = 0; i < rows.length; i++) {
      const parts = rows[i].split(":")

      // nmcli escapes a colon inside an SSID as "\:", so split on the first
      // field and the last one and rejoin what lies between.
      if (parts[0] === "*") {
        return parts.slice(1, parts.length - 1).join(":") + " " + parts[parts.length - 1] + "%"
      }
    }

    return ""
  }

  Process {
    id: probe
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "device", "wifi", "list"]

    stdout: StdioCollector {
      onStreamFinished: {
        const label = root.parse(this.text)

        if (label === "" && root.emptyRuns < 2) {
          root.emptyRuns += 1
          retry.restart()
          return
        }

        root.emptyRuns = 0
        root.connected = label !== ""
        root.ssid = label

        // Parsed output means the query worked, whatever an earlier run did.
        // Without this a single failed attempt at startup would tint the icon
        // for ever, alongside a perfectly good SSID.
        if (label !== "") root.failed = false
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.failed = true
        root.connected = false
        root.ssid = ""
      }
    }
  }

  Timer {
    id: retry
    interval: 700
    onTriggered: {
      probe.running = false
      probe.running = true
    }
  }

  Timer {
    running: true
    interval: 10000
    triggeredOnStart: true
    onTriggered: {
      // Optimistic: assume the next run works until it proves otherwise, so a
      // recovered backend stops showing the failure without waiting for a
      // second timer pass.
      root.failed = false
      probe.running = false
      probe.running = true
    }
  }

  // Declared as an id rather than built inline: `Component { ... }` is an
  // object declaration, so it cannot be passed as a call argument.
  Component {
    id: wifiPanel
    Network {}
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.wifi
    labelText: root.vertical || root.failed ? "" : root.ssid
    foreground: root.failed ? Theme.danger : Theme.fg
    tooltipText: root.failed
      ? "Wi-Fi unavailable — nmcli failed"
      : (root.resolved ? root.ssid : "Wi-Fi off")

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelHost.toggle(readout, wifiPanel)
      else if (button === Qt.RightButton) root.openSettings()
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