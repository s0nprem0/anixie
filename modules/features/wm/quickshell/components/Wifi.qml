import QtQuick
import ".."
import "../Ui"
import "../panels" as Panels
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wifi readout, from NetworkManager through Quickshell.Networking.
//
// This used to run `nmcli device wifi list` every ten seconds. That command is
// not a status query: when NetworkManager's cache is stale it triggers a real
// radio scan, which took about 3.2 seconds once in five runs and drew power each
// time. The Networking service reads the same state over D-Bus, and its device
// only scans while `scannerEnabled` is set — which is off unless the wifi panel
// asks for it.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: PanelRegistry.register("network", readout, wifiPanel)

  // The wifi device that is connected, if there is one.
  readonly property var device: {
    const list = Networking.devices.values || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === DeviceType.Wifi && list[i].connected) return list[i]
    }
    return null
  }

  // The network that device is on.
  readonly property var active: {
    if (!root.device) return null
    const nets = root.device.networks.values || []
    for (let i = 0; i < nets.length; i++) {
      if (nets[i].connected) return nets[i]
    }
    return null
  }

  readonly property bool connected: root.active !== null
  readonly property string ssid: root.active ? String(root.active.name) : ""
  readonly property int signal: root.active ? Math.round(Number(root.active.signalStrength) * 100) : 0

  // The service reports state rather than failing to run, so there is no
  // separate "query failed" case left. Kept as a property because the tooltip
  // still has a branch for it.
  readonly property bool failed: false

  readonly property bool resolved: connected && ssid !== ""

  // Offline hides the module, since a bar that reflows every time the network
  // drops is noisier than one that simply loses a module.
  wantsSlot: resolved

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.wifi

    // An icon, with the name and the strength in the tooltip. The bar's right
    // side is a row of glyphs; an SSID sitting in the middle of them was the
    // widest and least scannable thing on it, and the one piece of information
    // there that you read once rather than glance at.
    labelText: ""

    foreground: root.failed ? Theme.danger : Theme.fg
    tooltipText: root.failed
      ? "Wi-Fi unavailable · Super+Ctrl+W"
      : (root.resolved
        ? root.ssid + " · " + root.signal + "% · Super+Ctrl+W"
        : "Wi-Fi off · Super+Ctrl+W")

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("network")
      else if (button === Qt.RightButton) root.openSettings()
    }
  }

  // Declared as an id rather than built inline: `Component { ... }` is an
  // object declaration, so it cannot be passed as a call argument.
  Component {
    id: wifiPanel
    // Qualified: Quickshell.Networking has a `Network` of its own, and the later
    // import wins, which made this the service's type and failed the whole bar.
    Panels.Network {}
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
