import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Wi-Fi panel: the radio, what is in use, what is nearby, and a way to switch.
//
// Reads and actions come from Quickshell.Networking, which talks to
// NetworkManager over D-Bus. nmcli is kept for the few facts the service does
// not expose: the profile name for DNS, the gateway, VPN links, the band, and
// the QR.
//
// The shape follows the reference's network popup: a status header, the two
// radios side by side, then sections under a rule — Details, VPNs, Wi-Fi
// Networks and More. The details are folded away because they are what you read
// once, while the networks are what the panel is opened for; a network row
// opens its own actions in place rather than sending you to another surface.
// The hero still names the panel, because that is how every other panel in the
// shell begins.
Item {
  id: root

  // Reads and actions come from the service; the panel only keeps the things
  // the service does not expose (the profile name for DNS, the gateway, VPN
  // links, and the QR).
  readonly property var wifiDevice: NetworkHost.wifiDevice
  readonly property var networks: NetworkHost.networks
  readonly property string activeSsid: NetworkHost.activeSsid
  readonly property bool connected: NetworkHost.connected

  // The NetworkManager profile behind the SSID. The two are not the same: a
  // profile can be renamed, and every nmcli con verb (show, mod, up) takes the
  // profile name, not the SSID. It is still read with nmcli because the service
  // does not expose the profile name.
  property string activeConnection: ""

  readonly property bool scanning: NetworkHost.scanning

  readonly property bool failed: NetworkHost.unavailable
  readonly property string failure: NetworkHost.failure

  readonly property bool radioEnabled: NetworkHost.wifiEnabled
  readonly property bool radioBusy: NetworkHost.radioPending

  // The row whose action is running, and which action it is. The row renders
  // "Connecting…" / "Disconnecting…" so a click that takes a second is visibly
  // doing something rather than looking ignored.
  readonly property string actionSsid: NetworkHost.actionSsid
  readonly property string actionKind: NetworkHost.actionKind

  // The first line of the last action's failure. A connect that fails for any
  // reason other than a missing secret used to look exactly like one that
  // needed a password; this is where the difference is said out loud.
  property string actionError: ""

  // A secured network that would not join because it has no stored key. The
  // service can hand the key over directly, so this is a prompt rather than a
  // secret agent.
  property string askingSsid: ""

  // One action at a time. Two connects racing each other is not a faster connect,
  // it is two requests fighting over the device and neither result trustworthy.
  readonly property bool busy: NetworkHost.busy

  // ---- what the panel is showing ----
  //
  // The reference folds the connection facts and its less-used actions away, and
  // opens a network's actions where the network is. These three follow that:
  // details and More are closed until asked for, and one network at a time is
  // open because opening two turns the list into a wall of buttons.
  property bool detailsExpanded: false
  property bool moreExpanded: false
  property string expandedSsid: ""

  // ---- airplane ----
  //
  // Airplane is both radios off, not a separate rfkill switch: that is what the
  // two controls below can actually do without root, and a toggle that claimed
  // to block a radio it could not touch would be a lie. Bluetooth comes from the
  // same service the bar's Bluetooth widget uses, so the two never disagree.
  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothEnabled: root.bluetoothAdapter ? root.bluetoothAdapter.enabled : false
  readonly property bool airplaneMode: !root.radioEnabled && !root.bluetoothEnabled

  // ---- VPNs ----
  //
  // NetworkManager's own VPN, WireGuard and tun connections. Tailscale shows up
  // here as its tun link; the widget on the bar still owns the tailnet itself,
  // and this is the same connection seen from the network layer.
  property var vpns: []
  property bool vpnBusy: false
  property string pendingVpnName: ""
  property bool pendingVpnUp: false
  property bool restarting: false

  Connections {
    target: NetworkHost

    function onActionFailed(message) { root.actionError = message }
    function onSecretRequested(ssid) { root.askingSsid = ssid }
  }

  // ---- share by QR ----
  //
  // The QR holds the network password, so it is off by default, generated only
  // when switched on, and the file it draws is removed again when it is switched
  // off. `qrPath` is what SizedImage is given and only set once a file exists.
  property bool qrVisible: false
  property string qrPath: ""
  property string qrError: ""
  readonly property bool qrReady: root.qrPath !== ""

  // ---- password ----
  //
  // The QR is the shareable form; this is the plain password for the cases a
  // phone cannot scan. It is copied rather than shown, so the secret does not
  // stay on screen after the click.
  property bool passwordBusy: false
  property bool passwordCopied: false

  // ---- DNS ----
  //
  // Per connection, not global: nmcli keeps it on the connection profile, which
  // is why it follows the network rather than the machine. An empty list means
  // "whatever the router hands out", and that is a choice worth offering by name
  // — the alternative is a panel that can only ever add a resolver, never go
  // back to the one DHCP gave you.
  readonly property var dnsProviders: [
    { label: "Automatic", value: "", value6: "" },
    { label: "Cloudflare", value: "1.1.1.1 1.0.0.1", value6: "2606:4700:4700::1111 2606:4700:4700::1001" },
    { label: "Quad9", value: "9.9.9.9 149.112.112.112", value6: "2620:fe::fe 2620:fe::9" },
    { label: "Google", value: "8.8.8.8 8.8.4.4", value6: "2001:4860:4860::8888 2001:4860:4860::8844" }
  ]

  property string dns: ""
  property string dns6: ""
  property bool dnsBusy: false

  // ---- band ----
  //
  // NetworkManager keeps the preference on the connection profile. The current
  // band comes from the access point, while the selection is what the profile
  // will ask for on the next association.
  property string band: ""
  property var availableBands: []
  property string bandSelection: "auto"
  property bool bandBusy: false

  readonly property var bandOptions: {
    const labels = { "2.4": "2.4 GHz", "5": "5 GHz", "6": "6 GHz" }
    const options = [{ label: "Automatic", value: "auto" }]
    let listed = false

    for (let i = 0; i < root.availableBands.length; i++) {
      const value = root.availableBands[i]
      if (labels[value]) options.push({ label: labels[value], value: value })
      if (value === root.bandSelection) listed = true
    }

    if (root.bandSelection !== "auto" && !listed) {
      options.push({
        label: (labels[root.bandSelection] || root.bandSelection) + " (unavailable)",
        value: root.bandSelection
      })
    }

    return options
  }

  function bandIndex() {
    for (let i = 0; i < root.bandOptions.length; i++) {
      if (root.bandOptions[i].value === root.bandSelection) return i
    }
    return 0
  }

  function refreshBand() {
    if (!root.connected) {
      root.band = ""
      root.availableBands = []
      root.bandSelection = "auto"
      return
    }

    bandGet.running = false
    bandGet.running = true
  }

  function setBand(value) {
    if (value === root.bandSelection) return

    root.actionError = ""
    root.bandBusy = true
    bandSet.command = ["wifi", "band", value]
    bandSet.running = false
    bandSet.running = true
  }

  // What the connection actually is, rather than what it is called.
  property string address: ""
  property string gateway: ""
  property string wired: ""

  function refreshDetails() {
    root.refreshBand()
    root.refreshVpns()

    // Read by device, not by connection: the device is what the panel has, and
    // the answer includes the profile name, which is what the con verbs take.
    // It runs while disconnected too, so an Ethernet cable still shows.
    if (!root.wifiDevice) {
      root.activeConnection = ""
      root.address = ""
      root.gateway = ""
      root.wired = ""
      root.refreshDns()
      return
    }

    details.running = false
    details.running = true
  }

  function forget() {
    const item = root.networkFor(root.activeSsid)
    if (!item) return

    root.actionError = ""
    NetworkHost.forget(item)
  }

  // The network row for an SSID, for deciding whether a failed connect could
  // have been a missing key.
  function networkFor(ssid) {
    for (let i = 0; i < root.networks.length; i++) {
      if (root.networks[i].ssid === ssid) return root.networks[i]
    }
    return null
  }

  onWifiDeviceChanged: root.refreshDetails()

  // The service reports an address change when DHCP renews; the gateway and
  // profile name live in the same nmcli read, so one refresh covers all three.
  Connections {
    target: root.wifiDevice
    function onAddressChanged() { root.refreshDetails() }
  }

  // One read for the facts the service does not expose: the profile name, the
  // gateway, the other links that are up, and the VPN. The fields are asked for
  // one at a time because `-g A,B` prints every value of A before B, so a
  // connection with two addresses put the second address where the gateway was
  // read from.
  Process {
    id: details
    running: false
    command: ["sh", "-c",
      'nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null; echo ---; '
      + 'nmcli -g IP4.ADDRESS device show "$1" 2>/dev/null | head -1; echo ---; '
      + 'nmcli -g IP4.GATEWAY device show "$1" 2>/dev/null | head -1; echo ---; '
      + 'nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null | grep -E "^ethernet:" || true',
      "_", root.wifiDevice ? root.wifiDevice.name : ""]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = String(this.text).split("---")

        // `-g` is terse output and escapes `:` and `\`, so the profile name has
        // to be decoded before it is used as an argument to the con verbs.
        root.activeConnection = root.decodeSsid(String(parts[0] || "").trim())

        root.address = String(parts[1] || "").trim().split("/")[0]
        root.gateway = String(parts[2] || "").trim()

        let wired = ""
        const links = String(parts[3] || "").trim().split("\n")
        for (let i = 0; i < links.length; i++) {
          const fields = links[i].split(":")
          if (fields[1] === "connected") wired = root.decodeSsid(fields[2] || "connected")
        }

        root.wired = wired

        // DNS is a property of the profile, so it can only be read once the
        // profile name is known. Always, not only on a change: a details read
        // can land before the list has named the active network, and that read
        // would otherwise leave DNS empty until the next change.
        root.refreshDns()
      }
    }
  }

  // ---- VPNs ----
  //
  // One read for the list, then one action at a time. `-t` escapes separators in
  // a profile name, so the type and the active flag are taken from the two ends
  // of the line rather than by splitting the name on a colon it may contain.
  function refreshVpns() {
    vpnList.running = false
    vpnList.running = true
  }

  function toggleVpn(vpn) {
    if (!vpn || root.vpnBusy) return

    root.actionError = ""
    root.vpnBusy = true
    root.pendingVpnName = String(vpn.name || "")
    root.pendingVpnUp = !vpn.active
    vpnAction.command = ["nmcli", "connection", vpn.active ? "down" : "up", vpn.name]
    vpnAction.running = false
    vpnAction.running = true
  }

  Process {
    id: vpnList
    running: false
    command: ["sh", "-c", "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const out = []
        const lines = String(this.text || "").split("\n")

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (line === "") continue

          const activeAt = line.lastIndexOf(":")
          if (activeAt < 0) continue
          const typeAt = line.lastIndexOf(":", activeAt - 1)
          if (typeAt < 0) continue

          const name = root.decodeSsid(line.slice(0, typeAt))
          const type = line.slice(typeAt + 1, activeAt)
          if (name === "" || name === "lo") continue
          if (type !== "vpn" && type !== "wireguard" && type !== "tun") continue

          out.push({ name: name, type: type, active: line.slice(activeAt + 1) === "yes" })
        }

        root.vpns = out
      }
    }
  }

  Process {
    id: vpnAction
    running: false
    stderr: StdioCollector { id: vpnError }
    onExited: function (exitCode) {
      root.vpnBusy = false

      if (exitCode !== 0) {
        const message = String(vpnError.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not change the VPN"
      }

      if (exitCode === 0 && root.pendingVpnName !== "") {
        OsdHost.show("vpn", root.pendingVpnUp ? "VPN connected: " + root.pendingVpnName : "VPN disconnected: " + root.pendingVpnName, "", "", "", 1500)
      }
      root.pendingVpnName = ""

      root.refreshVpns()
      root.refreshDetails()
    }
  }

  Process {
    id: bandGet
    running: false
    command: ["wifi", "band"]
    stdout: StdioCollector {
      onStreamFinished: {
        let band = ""
        let available = []
        let selected = "auto"
        const lines = String(this.text || "").split("\n")

        for (let i = 0; i < lines.length; i++) {
          if (lines[i] === "") continue
          const fields = lines[i].split("\t")

          if (fields[0] === "band") {
            band = fields[1] || ""
          } else if (fields[0] === "available") {
            available = String(fields[1] || "")
              .split(" ")
              .filter(function (value) { return value !== "" })
          } else if (fields[0] === "selected") {
            selected = fields[1] || "auto"
          }
        }

        root.band = band
        root.availableBands = available
        root.bandSelection = selected
      }
    }
  }

  Process {
    id: bandSet
    running: false
    stderr: StdioCollector { id: bandSetErr }
    onExited: function (exitCode) {
      root.bandBusy = false

      if (exitCode !== 0) {
        const message = String(bandSetErr.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not change the Wi-Fi band"
      }

      root.refreshBand()
      root.refreshDetails()
    }
  }

  // Addresses as a set, so "1.1.1.1 1.0.0.1" and "1.0.0.1,1.1.1.1" are the same
  // answer rather than two different ones.
  function dnsKey(value) {
    return String(value || "")
      .split(/[,\s]+/)
      .filter(function (part) { return part !== "" })
      .sort()
      .join(" ")
  }

  function dnsIndex() {
    const current = root.dnsKey(root.dns)
    const current6 = root.dnsKey(root.dns6)
    for (let i = 0; i < root.dnsProviders.length; i++) {
      const provider = root.dnsProviders[i]
      if (root.dnsKey(provider.value) === current && root.dnsKey(provider.value6) === current6) {
        return i
      }
    }
    return -1
  }

  function refreshDns() {
    if (!root.connected || root.activeConnection === "") {
      root.dns = ""
      root.dns6 = ""
      return
    }

    dnsGet.running = false
    dnsGet.running = true
  }

  function setDns(provider) {
    if (!provider || root.activeConnection === "") return

    root.actionError = ""
    root.dnsBusy = true
    dnsSet.command = ["wifi", "dns", "set", provider.value || "", provider.value6 || ""]
    dnsSet.running = false
    dnsSet.running = true
  }

  Process {
    id: dnsGet
    running: false
    command: ["wifi", "dns"]
    stdout: StdioCollector {
      onStreamFinished: {
        let v4 = ""
        let v6 = ""
        const lines = String(this.text || "").split("\n")

        for (let i = 0; i < lines.length; i++) {
          if (lines[i] === "") continue
          const fields = lines[i].split("\t")
          if (fields[0] === "ipv4") v4 = fields[1] || ""
          else if (fields[0] === "ipv6") v6 = fields[1] || ""
        }

        root.dns = v4
        root.dns6 = v6
      }
    }
  }

  Process {
    id: dnsSet
    running: false
    stderr: StdioCollector { id: dnsErr }
    onExited: function (exitCode) {
      root.dnsBusy = false
      if (exitCode !== 0) {
        const message = String(dnsErr.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not change DNS"
      }
      root.refreshDns()
      root.refreshDetails()
    }
  }

  // refreshDetails reads the profile name and calls this once it is known, so
  // DNS is never read against the previous network's name. A code for one
  // network is not a code for another, so a change takes it away.
  onActiveSsidChanged: {
    root.refreshDetails()
    root.passwordCopied = false
    if (root.qrVisible) root.setQr(false)
  }

  readonly property int qrSize: Style.space(180)

  // What the empty list means, said in the list rather than in a line below it.
  // Four reasons to be empty and each says which it is, including "there is
  // nothing to connect to because the radio is off" — which was the case that
  // used to render nothing at all, because the list has no height to say it in.
  readonly property string emptyMessage: !root.radioEnabled
    ? "Wireless is off"
    : (root.failed ? "" : (root.scanning ? "Scanning…" : "No networks found"))

  function copyPassword() {
    root.actionError = ""
    root.passwordBusy = true
    root.passwordCopied = false
    passwordCopy.running = false
    passwordCopy.running = true
  }

  function setQr(on) {
    root.qrVisible = on

    if (on) {
      root.qrPath = ""
      root.qrError = ""
      qrQuery.running = false
      qrQuery.running = true
    } else {
      // Stop a generation that is still running before removing the file.
      // Otherwise it can finish after the removal and leave the password on
      // disk with the toggle that made it off.
      qrQuery.running = false
      root.qrPath = ""
      root.qrError = ""
      // Take the image away with the toggle. Leaving a password-bearing QR in
      // the state directory after the switch that put it there is off is the
      // kind of thing nobody remembers to clean up.
      rmQr.running = true
    }
  }

  Process {
    id: qrQuery
    command: ["wifi", "qr"]
    stdout: StdioCollector {
      onStreamFinished: {
        const path = String(this.text || "").trim()

        // The toggle may have gone off while the code was being written; the
        // file that just appeared is not wanted.
        if (!root.qrVisible) {
          root.qrPath = ""
          rmQr.running = true
          return
        }

        root.qrPath = path
      }
    }
    stderr: StdioCollector { id: qrErr }
    onExited: function (exitCode) {
      // Killed by turning the toggle off; its exit is not a failure to show.
      if (!root.qrVisible) return

      if (exitCode === 0) {
        root.qrError = ""
        return
      }

      // The script says why (open network, 802.1X, no encoder); a generic line
      // only when it does not.
      const message = String(qrErr.text || "").trim().split("\n")[0]
      root.qrPath = ""
      root.qrError = message !== "" ? message : "Could not read the network password"
    }
  }

  Process {
    id: rmQr
    command: root.stateDir !== ""
      ? ["sh", "-c", 'rm -f "$1"', "_", root.stateDir + "/wifi-qr.png"]
      : ["true"]
  }

  Process {
    id: passwordCopy
    running: false
    command: ["wifi", "password", "--copy"]
    stderr: StdioCollector { id: passwordCopyErr }
    onExited: function (exitCode) {
      root.passwordBusy = false

      if (exitCode !== 0) {
        const message = String(passwordCopyErr.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not copy the network password"
        return
      }

      root.passwordCopied = true
      passwordCopiedTimer.restart()
    }
  }

  Timer {
    id: passwordCopiedTimer
    interval: 2000
    onTriggered: root.passwordCopied = false
  }

  readonly property string stateDir: {
    const state = Quickshell.env("XDG_STATE_HOME")
    if (state) return state + "/anixie"

    const home = Quickshell.env("HOME")
    return home !== "" ? home + "/.local/state/anixie" : ""
  }

  function decodeSsid(value) {
    return String(value).replace(/\\(.)/g, "$1")
  }

  // ---- commands ----
  //
  // The service owns the list and the actions; these are the small wrappers the
  // UI calls, plus the one details read that still needs nmcli.

  function retry() {
    root.actionError = ""
    NetworkHost.scan()
  }

  function rescan() {
    if (!root.radioEnabled) return

    root.actionError = ""
    NetworkHost.scan()
  }

  function connect(ssid) {
    const item = typeof ssid === "string" ? root.networkFor(ssid) : ssid
    if (!item || !root.radioEnabled) return

    root.actionError = ""
    NetworkHost.connect(item)
  }

  function disconnect(ssid) {
    const item = typeof ssid === "string" ? root.networkFor(ssid) : ssid
    if (!item) return

    root.actionError = ""
    NetworkHost.disconnect(item)
  }

  function connectSecret(secret) {
    if (root.askingSsid === "" || secret === "") return

    const item = root.networkFor(root.askingSsid)
    root.askingSsid = ""
    root.actionError = ""
    if (item) NetworkHost.connectWithPsk(item, secret)
  }

  function setRadio(on) {
    root.actionError = ""
    NetworkHost.setWifiEnabled(on)

    // Nothing the radio was connected to survives it going off, so neither does
    // the code for that connection.
    if (!on && root.qrVisible) root.setQr(false)
  }

  function setAirplane(on) {
    root.actionError = ""
    root.setRadio(!on)
    if (root.bluetoothAdapter) root.bluetoothAdapter.enabled = !on
  }

  // Cycling the radio is the fix for the state a network manager occasionally
  // gets stuck in, and doing it from here saves opening a terminal for one
  // command. The delay is the same half second the CLI's own helper uses: long
  // enough for the device to go down, short enough not to feel like a hang.
  function restartWifi() {
    if (root.restarting || !root.radioEnabled) return

    root.actionError = ""
    root.restarting = true
    NetworkHost.setWifiEnabled(false)
    restartOn.restart()
  }

  Timer {
    id: restartOn
    interval: 500
    onTriggered: {
      NetworkHost.setWifiEnabled(true)
      root.restarting = false
    }
  }

  Component.onCompleted: {
    // A code from a previous run is a password left behind; the toggle that
    // made it is off in this fresh panel.
    if (root.stateDir !== "") rmQr.running = true

    NetworkHost.activate()
    root.refreshDetails()
  }

  Component.onDestruction: {
    NetworkHost.deactivate()
    qrQuery.running = false
    if (root.stateDir !== "") rmQr.running = true
  }

  function bandLabel(item) {
    if (!item) return ""

    const bands = item.inUse && root.band !== ""
      ? [root.band]
      : (item.bands || [])

    return bands.length > 0 ? bands.join("/") + " GHz" : ""
  }

  // Signal bars: four steps, filled by where the percentage lands.
  function signalLevel(percent) {
    if (percent >= 70) return 4
    if (percent >= 45) return 3
    if (percent >= 20) return 2
    return 1
  }

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- status ----
    //
    // The reference leads with the state rather than with a switch: whether this
    // machine is on the network is what the panel is about, and the radios are
    // the controls underneath that.
    PanelHero {
      width: card.contentWidth
      glyph: Util.wifi
      title: root.connected ? "Wi-Fi Connected" : "Wi-Fi"
      subtitle: root.connected
        ? root.activeSsid + " · Signal " + NetworkHost.signal + "%"
        : (root.radioEnabled ? "Not connected" : "Wireless off")
    }

    // The last action's own failure — a connect, a DNS change, a forgotten
    // profile — next to the thing it happened to. The "Unavailable" below is for
    // the read, not for these.
    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.actionError !== ""
      text: root.actionError
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    // The status line doubles as the error surface: when nmcli is broken it is
    // the only place the reason can be read, since the list below is empty for
    // exactly the same reason either way.
    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.failed
      text: "Unavailable"
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    // What nmcli said, under the fact that it failed. A failure that explains
    // itself is not the same as one that does not, and a half-dozen lines of
    // nmcli's own prose is not something to put in a panel either: the first
    // line, which is the reason.
    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.failed && root.failure !== ""
      text: String(root.failure).split("\n")[0]
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    // A failure with no way out of it is a dead end. nmcli exits non-zero for a
    // transient reason often enough — NetworkManager restarting, the device still
    // coming up — and the one thing that always helps is asking again.
    PanelActionButton {
      width: card.contentWidth
      visible: root.failed
      label: "Try again"
      navigational: false
      onClicked: root.retry()
    }

    PanelSeparator {}

    // ---- the radios ----
    //
    // Side by side, like the reference's "Wi-Fi: On  Airplane: Off" line: they
    // are two halves of the same decision, and putting them in one run keeps the
    // panel from spending a full row on each.
    Row {
      width: card.contentWidth
      spacing: Style.space(8)

      PanelActionButton {
        width: (card.contentWidth - Style.space(8)) / 2
        label: "Wi-Fi"
        value: root.radioEnabled ? "On" : "Off"
        navigational: false
        available: !root.radioBusy
        onClicked: root.setRadio(!root.radioEnabled)
      }

      PanelActionButton {
        width: (card.contentWidth - Style.space(8)) / 2
        label: "Airplane"
        value: root.airplaneMode ? "On" : "Off"
        navigational: false
        onClicked: root.setAirplane(!root.airplaneMode)
      }
    }

    PanelSeparator {
      visible: root.connected
    }

    // ---- details ----
    //
    // Folded away because the facts under it are what you read once, while the
    // networks below are what the panel is opened for. It also keeps the panel
    // short enough that the list is still on screen when it opens.
    PanelActionButton {
      width: card.contentWidth
      visible: root.connected
      label: "Details"
      value: root.detailsExpanded ? "hide" : "show"
      navigational: false
      onClicked: root.detailsExpanded = !root.detailsExpanded
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(8)
      visible: root.connected && root.detailsExpanded

      PanelRow {
        width: parent.width
        visible: root.address !== ""
        label: "IP"
        value: root.address
      }

      PanelRow {
        width: parent.width
        visible: root.gateway !== ""
        label: "Gateway"
        value: root.gateway
      }

      PanelRow {
        width: parent.width
        visible: NetworkHost.security !== ""
        label: "Security"
        value: NetworkHost.security
      }

      // The links the Wi-Fi panel is not about, but is the only network surface
      // the shell has: an Ethernet cable on a dock changes the answer to "is
      // this machine online".
      PanelRow {
        width: parent.width
        visible: root.wired !== ""
        label: "Wired"
        value: root.wired
      }

      PanelRow {
        id: dnsRow
        width: parent.width
        hasControl: true
        label: "DNS"

        Dropdown {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: dnsRow.controlWidth
          model: root.dnsProviders
          placeholder: "custom"
          enabled: !root.dnsBusy
          currentIndex: root.dnsIndex()
          onActivated: function (index) { root.setDns(root.dnsProviders[index]) }
        }
      }

      PanelRow {
        id: bandRow
        width: parent.width
        visible: root.band !== ""
        hasControl: true
        label: "Band"

        Dropdown {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: bandRow.controlWidth
          model: root.bandOptions
          enabled: !root.bandBusy
          currentIndex: root.bandIndex()
          onActivated: function (index) { root.setBand(root.bandOptions[index].value) }
        }
      }

      PanelSeparator {}

      // The QR, behind a toggle. It carries the network's password in the clear,
      // so it is drawn only while this is on, and generated only then — the image
      // is not sitting in the state directory waiting for a panel to be open.
      Toggle {
        id: qrToggle
        width: parent.width
        height: implicitHeight
        label: "Share this network"
        description: "a QR code another device can scan to join"
        checked: root.qrVisible
        onToggled: root.setQr(!root.qrVisible)
      }

      PanelActionButton {
        width: parent.width
        label: root.passwordCopied ? "Password copied" : (root.passwordBusy ? "Copying…" : "Copy password")
        outlined: true
        navigational: false
        available: !root.passwordBusy
        onClicked: root.copyPassword()
      }

      // The box is the size the code is drawn at, not the size of the file behind
      // it: an Image's implicit height is the source's own, and a QR that arrives
      // as 512px made a 512px row that the panel then had to cut.
      Item {
        width: parent.width
        height: root.qrVisible && root.qrReady ? root.qrSize : 0
        visible: height > 0

        SizedImage {
          id: qrImage
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.qrSize
          height: root.qrSize
          source: root.qrPath
          fillMode: Image.PreserveAspectFit
        }
      }

      Text {
        width: parent.width
        height: implicitHeight
        visible: root.qrVisible && root.qrError !== ""
        text: root.qrError
        color: Theme.danger
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }

    PanelSeparator {}

    // ---- VPNs ----
    //
    // NetworkManager's links that are not the Wi-Fi one. The action is the whole
    // row, the way the reference puts "disconnect" at the end of its VPN lines:
    // there is one thing to do to a VPN and no reason to aim at a word for it.
    PanelSectionHeader {
      width: card.contentWidth
      label: "VPNs & Proxies"
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.vpns.length === 0
      text: "None"
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(2)

      Repeater {
        model: root.vpns

        delegate: PanelActionButton {
          required property var modelData

          width: card.contentWidth
          label: modelData.name + " (" + modelData.type + ")"
          value: (modelData.active ? "Connected" : "Disconnected")
            + " · " + (modelData.active ? "disconnect" : "connect")
          navigational: false
          available: !root.vpnBusy
          onClicked: root.toggleVpn(modelData)
        }
      }
    }

    // ---- what is nearby ----
    //
    // The rescan belongs to the list it rescans: at the end of the heading rather
    // than in a row of its own at the bottom, which read as a label and put the
    // one control for the list a screenful away from the list.
    PanelSectionHeader {
      width: card.contentWidth
      label: "Wi-Fi Networks"
      action: root.scanning ? "Scanning…" : "Rescan"
      actionEnabled: root.radioEnabled && !root.scanning && !root.failed && !root.busy
      onActionTriggered: root.rescan()
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(2)

      Repeater {
        model: root.networks

        delegate: Column {
          id: netRow
          required property var modelData

          readonly property bool inFlight: root.actionSsid === netRow.modelData.ssid && root.busy
          readonly property bool expanded: root.expandedSsid === netRow.modelData.ssid
          readonly property var network: netRow.modelData.network

          width: card.contentWidth
          spacing: Style.space(2)

          ChoiceRow {
            width: parent.width
            height: Style.space(28)
            available: root.radioEnabled && !root.busy

            // Only for networks that need a key. An open network gets no glyph
            // rather than an open padlock: the absence says "open" more quietly
            // than a symbol repeated on every row would.
            glyph: netRow.modelData.secured ? Util.lock : ""
            label: netRow.inFlight
              // The row says what it is doing while it does it. Without this a
              // click on a network that takes a second looks like nothing
              // happened.
              ? (root.actionKind === "connect" ? "Connecting…" : "Disconnecting…")
              : netRow.modelData.ssid
            selected: netRow.modelData.inUse && !netRow.inFlight

            // Opening the row is what picks it now, rather than connecting on
            // the first click: the reference puts Connect, Forget and Auto under
            // the network, and a list where one click both chooses and joins is
            // a list you cannot look at without acting on.
            onClicked: root.expandedSsid = netRow.expanded ? "" : netRow.modelData.ssid

            Row {
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: root.bandLabel(netRow.modelData)
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }

              // Four ascending bars, the filled count set by the signal
              // percentage.
              Row {
                spacing: 2

                Repeater {
                  model: 4
                  delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 4 + index * 3
                    radius: Theme.cornerRadius
                    // Standing on the same line, not floating around their own
                    // middles: centre-aligned bars of four different heights
                    // read as dashes, not as a staircase, which is the whole
                    // point of the glyph.
                    anchors.bottom: parent.bottom
                    color: index < root.signalLevel(netRow.modelData.signal)
                      ? (netRow.modelData.inUse ? Theme.accent : Theme.muted)
                      : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: netRow.expanded

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: netRow.modelData.secured && !netRow.modelData.inUse

              onVisibleChanged: {
                if (!visible) return
                inlineSecretField.text = ""
                Qt.callLater(function () { inlineSecretField.forceActiveFocus() })
              }

              Text {
                width: parent.width
                text: "Password for " + netRow.modelData.ssid
                color: Theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              TextField {
                id: inlineSecretField
                width: parent.width
                echoMode: TextInput.Password
                placeholderText: "network password"
                Keys.onEscapePressed: root.askingSsid = ""
                onAccepted: root.connectSecret(inlineSecretField.text)
              }

              PanelActionButton {
                width: parent.width
                label: "Connect"
                navigational: false
                available: inlineSecretField.text !== ""
                onClicked: {
                  if (inlineSecretField.text !== "")
                    NetworkHost.connectWithPsk(netRow.modelData, inlineSecretField.text)
                  else
                    root.connect(netRow.modelData.ssid)
                }
              }

              PanelActionButton {
                width: parent.width
                label: "Cancel"
                navigational: false
                onClicked: root.askingSsid = ""
              }
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(4)

              TextButton {
                label: netRow.modelData.inUse ? "Disconnect" : "Connect"
                active: netRow.modelData.inUse
                available: !root.busy
                onClicked: {
                  if (netRow.modelData.inUse) {
                    root.expandedSsid = ""
                    root.disconnect(netRow.modelData.ssid)
                  } else if (netRow.modelData.secured && inlineSecretField.text !== "") {
                    root.expandedSsid = netRow.modelData.ssid
                    NetworkHost.connectWithPsk(netRow.modelData, inlineSecretField.text)
                  } else {
                    root.expandedSsid = netRow.modelData.ssid
                    root.connect(netRow.modelData.ssid)
                  }
                }
              }

              TextButton {
                visible: netRow.network ? netRow.network.known : false
                label: "Forget"
                danger: true
                available: !root.busy
                onClicked: {
                  root.expandedSsid = ""
                  root.actionError = ""
                  NetworkHost.forget(netRow.modelData)
                }
              }

              TextButton {
                visible: netRow.network ? netRow.network.known : false
                label: "Auto: " + (netRow.network && netRow.network.autoconnect ? "On" : "Off")
                active: !!(netRow.network && netRow.network.autoconnect)
                onClicked: {
                  if (netRow.network) netRow.network.autoconnect = !netRow.network.autoconnect
                }
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Security: "
                + (netRow.network ? NetworkHost.securityLabel(netRow.network.security) : "")
                + (root.bandLabel(netRow.modelData) !== "" ? " · " + root.bandLabel(netRow.modelData) : "")
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }
        }
      }
    }

    // What an empty list means, rather than an empty box. There is nothing to
    // draw an expansion under, so the reason stands on its own.
    Text {
      width: card.contentWidth
      visible: root.networks.length === 0 && root.emptyMessage !== ""
      text: root.emptyMessage
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      renderType: Text.NativeRendering
    }

    // ---- more ----
    //
    // The reference keeps its less-used actions behind one fold, and so does
    // this: cycling the radio is the one thing that clears the state a network
    // manager occasionally wedges in, and forgetting the current network is
    // destructive enough that it should not sit next to the list.
    PanelSeparator {}

    PanelActionButton {
      width: card.contentWidth
      label: "More"
      value: root.moreExpanded ? "hide" : "show"
      navigational: false
      onClicked: root.moreExpanded = !root.moreExpanded
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(8)
      visible: root.moreExpanded

      PanelActionButton {
        width: parent.width
        label: root.restarting ? "Restarting…" : "Restart Wi-Fi"
        navigational: false
        available: !root.restarting && root.radioEnabled && !root.busy
        onClicked: root.restartWifi()
      }

      PanelActionButton {
        width: parent.width
        visible: root.connected && root.networkFor(root.activeSsid) !== null
        label: "Forget this network"
        danger: true
        outlined: true
        navigational: false
        available: !root.busy
        onClicked: root.forget()
      }
    }
  }
}