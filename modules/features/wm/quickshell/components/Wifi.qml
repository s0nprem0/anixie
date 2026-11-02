import QtQuick
import ".."
import "../Ui"
import "../panels" as Panels
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wifi readout, from NetworkManager through Quickshell.Networking.
//
// Uses D-Bus via Quickshell.Networking; no periodic nmcli scans.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: root.registerPanel("network", readout, wifiPanel)

  // Ethernet device
  readonly property var wiredDevice: {
    const list = Networking.devices.values || []
    for (let i = 0; i < list.length; i++) {
      const d = list[i]
      if (!d) continue
      if (d.type === DeviceType.Wired && d.connected) return d
    }
    return null
  }
  readonly property bool wired: root.wiredDevice !== null
  readonly property string wiredName: root.wired ? String(root.wiredDevice.name || "Ethernet") : ""

  // Wi-Fi device
  readonly property var wifiDevice: {
    const list = Networking.devices.values || []
    for (let i = 0; i < list.length; i++) {
      const d = list[i]
      if (!d) continue
      if (d.type === DeviceType.Wifi) return d
    }
    return null
  }

  readonly property bool wifiEnabled: NetworkHost ? !!NetworkHost.wifiEnabled : (Networking.wifiEnabled !== undefined ? !!Networking.wifiEnabled : true)
  readonly property bool wifiHardwareEnabled: NetworkHost ? !!NetworkHost.wifiHardwareEnabled : (Networking.wifiHardwareEnabled !== undefined ? !!Networking.wifiHardwareEnabled : true)
  readonly property bool wifiAvailable: root.wifiDevice !== null && root.wifiHardwareEnabled

  // Connected Wi-Fi network
  readonly property var wifiActive: {
    if (!root.wifiDevice || !root.wifiEnabled) return null
    const nets = root.wifiDevice.networks ? (root.wifiDevice.networks.values || []) : []
    for (let i = 0; i < nets.length; i++) {
      if (nets[i] && nets[i].connected) return nets[i]
    }
    return null
  }

  readonly property bool wifiConnected: root.wifiActive !== null
  readonly property string ssid: root.wifiActive ? String(root.wifiActive.name || "") : ""
  readonly property real signalRaw: root.wifiConnected ? Number(root.wifiActive.signalStrength) : NaN
  readonly property int signal: (isFinite(root.signalRaw))
    ? Math.max(0, Math.min(100, Math.round(root.signalRaw * 100)))
    : -1

  readonly property bool wifiConnecting: root.wifiDevice && root.wifiDevice.state !== undefined
    ? (Number(root.wifiDevice.state) === 3 || Number(root.wifiDevice.state) === 4 || Number(root.wifiDevice.state) === 7 || Number(root.wifiDevice.state) === 40)
    : false

  // Connectivity state
  readonly property bool anyConnected: root.wired || root.wifiConnected
  readonly property bool wifiDisabled: !root.wifiEnabled || !root.wifiHardwareEnabled
  readonly property bool networkingUnavailable: NetworkHost ? !!NetworkHost.unavailable : (Networking.backend === NetworkBackendType.None)

  // Signal strength levels (shared thresholds with panel intent)
  readonly property int level: {
    if (root.wired) return 4
    if (!root.wifiConnected || root.signal < 0) return 0
    if (root.signal >= 70) return 4
    if (root.signal >= 45) return 3
    if (root.signal >= 20) return 2
    return 1
  }

  readonly property bool weakSignal: root.wifiConnected && !root.wired && root.signal >= 0 && root.signal < 20
  readonly property bool lowSignal: root.wifiConnected && !root.wired && root.signal >= 0 && root.signal < 45

  // Keep accessible while disconnected
  wantsSlot: true

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  WidgetButton {
    id: readout
    contextMenu: [
      { label: "Network panel", glyph: Util.wifi, action: function () { PanelRegistry.toggle("network", readout) } },
      { label: "Wi-Fi settings", action: function () { root.openSettings() } }
    ]
    anchors.centerIn: parent
    keepSpace: true
    fixedWidth: Style.bar.iconSlot
    fixedHeight: Style.bar.iconSlot
    text: ""
    labelVisible: false
    hasVisualContent: true

    // Ethernet shown when present (priority visual)
    OpticalGlyph {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      visible: root.wired
      text: Util.ethernet
      fontSize: Style.bar.iconFont
      paintedSize: Style.bar.iconSize
      color: readout.foreground
    }

    // Wi-Fi bars when not wired
    Row {
      anchors.centerIn: parent
      visible: !root.wired
      spacing: 2

      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          width: 3
          height: 4 + index * 3
          radius: Theme.cornerRadius
          anchors.bottom: parent.bottom
          color: index < root.level
            ? readout.foreground
            : Qt.rgba(readout.foreground.r, readout.foreground.g, readout.foreground.b, root.wifiConnecting ? 0.18 : 0.12)
          opacity: root.wifiDisabled ? 0.4 : 1.0
        }
      }
    }

    foreground: root.networkingUnavailable ? Theme.danger : (root.weakSignal ? Theme.muted : Theme.fg)
    tooltipText: {
      if (root.networkingUnavailable) return "Network unavailable · Super+Ctrl+W"
      if (root.wired && root.wifiConnected) {
        return "Ethernet · " + root.wiredName + " · Wi-Fi " + root.ssid + " (" + root.signal + "%) · Super+Ctrl+W"
      }
      if (root.wired) {
        return "Ethernet · " + root.wiredName + " · Super+Ctrl+W"
      }
      if (root.wifiDisabled) {
        return "Wi-Fi disabled · Super+Ctrl+W"
      }
      if (root.wifiConnecting) {
        return "Wi-Fi connecting… · Super+Ctrl+W"
      }
      if (root.wifiConnected && root.signal >= 0) {
        return root.ssid + " · " + root.signal + "% · Super+Ctrl+W"
      }
      if (root.wifiConnected) {
        return root.ssid + " · Signal unknown · Super+Ctrl+W"
      }
      return "Network not connected · Super+Ctrl+W"
    }

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        PanelRegistry.toggle("network", readout)
      }
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
