pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// NetworkManager through Quickshell's D-Bus service.
//
// The network panel used to be a stack of nmcli processes and timers: a list
// read every ten seconds, a device read, a radio read, a scan process, and an
// action process, all parsing terse output. The service already keeps that state
// and emits changes, so the panel binds to it instead. nmcli is left where the
// service has no answer — the profile name for DNS, the gateway, VPN links, and
// the password-bearing QR — rather than for everything.
//
// Scanning is opt-in. Quickshell's WifiDevice only scans while `scannerEnabled`
// is set, which is why opening the panel turns it on and closing it turns it
// off; the bar's readout never starts a scan.
QtObject {
  id: root

  readonly property var devices: Networking.devices.values || []

  readonly property var wifiDevice: {
    for (let i = 0; i < root.devices.length; i++) {
      if (root.devices[i].type === DeviceType.Wifi) return root.devices[i]
    }
    return null
  }

  readonly property var wiredDevice: {
    for (let i = 0; i < root.devices.length; i++) {
      if (root.devices[i].type === DeviceType.Wired && root.devices[i].connected) return root.devices[i]
    }
    return null
  }

  readonly property var activeNetwork: {
    if (!root.wifiDevice) return null
    const list = root.wifiDevice.networks.values || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].connected) return list[i]
    }
    return null
  }

  readonly property string activeSsid: root.activeNetwork ? String(root.activeNetwork.name || "") : ""
  readonly property bool connected: root.activeSsid !== ""
  readonly property int signal: root.activeNetwork
    ? Math.round(Number(root.activeNetwork.signalStrength || 0) * 100)
    : 0

  // One row per name. A network broadcast by the 2.4 and 5 GHz radios is the
  // same choice twice; the connected one wins, otherwise the stronger one does,
  // and the pair counts as secured if either half is.
  readonly property var networks: {
    const device = root.wifiDevice
    if (!device) return []

    const list = device.networks.values || []
    const byName = {}

    for (let i = 0; i < list.length; i++) {
      const network = list[i]
      const ssid = String(network.name || "")
      if (ssid === "") continue

      const candidate = {
        ssid: ssid,
        signal: Math.round(Number(network.signalStrength || 0) * 100),
        secured: network.security !== WifiSecurityType.Open,
        inUse: network.connected,
        network: network
      }

      const seen = byName[ssid]
      if (!seen) {
        byName[ssid] = candidate
        continue
      }

      const takesIt = (candidate.inUse && !seen.inUse)
        || (candidate.inUse === seen.inUse && candidate.signal > seen.signal)

      const winner = takesIt ? candidate : seen
      winner.secured = winner.secured || seen.secured
      byName[ssid] = winner
    }

    const unique = Object.keys(byName).map(function (name) { return byName[name] })
    unique.sort(function (a, b) {
      if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
      return b.signal - a.signal
    })
    return unique
  }

  function networkFor(ssid) {
    for (let i = 0; i < root.networks.length; i++) {
      if (root.networks[i].ssid === ssid) return root.networks[i]
    }
    return null
  }

  // ---- radio ----

  property bool radioPending: false
  property bool radioTarget: false

  // Answer the click at once, then let the service's read-back confirm it. A
  // switch that waits for a D-Bus round trip reads as broken even when it is
  // only slow.
  readonly property bool wifiEnabled: root.radioPending ? root.radioTarget : Networking.wifiEnabled
  readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled

  readonly property bool unavailable: Networking.backend === NetworkBackendType.None
  readonly property string failure: root.unavailable ? "NetworkManager is not available" : ""

  function setWifiEnabled(on) {
    if (on === root.wifiEnabled) return
    root.radioPending = true
    root.radioTarget = on
    Networking.wifiEnabled = on
    radioTimeout.restart()
  }

  property Timer radioTimeout: Timer {
    interval: 3000
    onTriggered: root.radioPending = false
  }

  property Connections networkingConnections: Connections {
    target: Networking

    function onWifiEnabledChanged() {
      if (!root.radioPending) return
      if (Networking.wifiEnabled === root.radioTarget) {
        root.radioPending = false
      } else {
        root.radioPending = false
        root.actionFailed("Could not change the radio")
      }
    }
  }

  // ---- scanning ----
  //
  // More than one panel can be open on more than one screen, so the scanner is
  // counted rather than switched off by whichever panel closes first.

  property int scannerUsers: 0
  property bool scanning: false

  function activate() {
    root.scannerUsers += 1
    root.updateScanner()
    root.scan()
  }

  function deactivate() {
    root.scannerUsers = Math.max(0, root.scannerUsers - 1)
    root.updateScanner()
    if (root.scannerUsers === 0) root.scanning = false
  }

  function updateScanner() {
    if (!root.wifiDevice) return
    root.wifiDevice.scannerEnabled = root.scannerUsers > 0
  }

  function scan() {
    if (!root.wifiDevice || !root.wifiEnabled) return

    // Turning the scanner off and on is what asks for a fresh scan; leaving it
    // on only keeps the existing list current.
    root.wifiDevice.scannerEnabled = false
    root.scanning = true
    Qt.callLater(function () {
      if (root.wifiDevice && root.scannerUsers > 0) root.wifiDevice.scannerEnabled = true
    })
    scanTimeout.restart()
  }

  property Timer scanTimeout: Timer {
    interval: 3000
    onTriggered: root.scanning = false
  }

  onWifiDeviceChanged: {
    if (root.scannerUsers > 0) root.updateScanner()
  }

  // ---- actions ----

  property var actionNetwork: null
  property string actionSsid: ""
  property string actionKind: ""
  readonly property bool busy: root.actionKind !== ""

  signal actionFailed(string message)
  signal secretRequested(string ssid)

  function connect(item) {
    const network = item && item.network ? item.network : item
    if (!network || !root.wifiEnabled) return
    root.startAction(network, "connect")
    network.connect()
  }

  function connectWithPsk(item, psk) {
    const network = item && item.network ? item.network : item
    if (!network || psk === "" || !root.wifiEnabled) return
    root.startAction(network, "connect")
    network.connectWithPsk(psk)
  }

  function disconnect(item) {
    const network = item && item.network ? item.network : item
    if (!network) return
    root.startAction(network, "disconnect")
    network.disconnect()
  }

  function forget(item) {
    const network = item && item.network ? item.network : item
    if (!network) return
    root.startAction(network, "forget")
    network.forget()
    root.finishAction()
  }

  function startAction(network, kind) {
    root.actionNetwork = network
    root.actionSsid = String(network.name || "")
    root.actionKind = kind
    actionTimeout.restart()
  }

  function finishAction() {
    actionTimeout.stop()
    root.actionKind = ""
    root.actionSsid = ""
    root.actionNetwork = null
  }

  property Timer actionTimeout: Timer {
    interval: 15000
    onTriggered: {
      if (!root.busy) return
      root.actionFailed("NetworkManager did not answer")
      root.finishAction()
    }
  }

  property Connections actionConnections: Connections {
    target: root.actionNetwork

    function onConnectionFailed(reason) {
      const network = root.actionNetwork
      if (!network) return

      const ssid = String(network.name || "")
      if (reason === ConnectionFailReason.NoSecrets) {
        root.secretRequested(ssid)
        root.actionFailed("Could not join " + ssid + ". Check the password.")
      } else if (reason === ConnectionFailReason.WifiAuthTimeout) {
        root.actionFailed("Could not join " + ssid + ". Check the password.")
      } else {
        root.actionFailed("Could not " + (root.actionKind === "disconnect" ? "disconnect" : "connect"))
      }
      root.finishAction()
    }

    function onStateChanged() {
      const network = root.actionNetwork
      if (!network) return

      if (root.actionKind === "connect" && network.connected) root.finishAction()
      else if (root.actionKind === "disconnect" && !network.connected) root.finishAction()
    }
  }
}
