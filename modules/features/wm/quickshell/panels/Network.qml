import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "Nmcli.js" as Nmcli

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

  // Request generation for the details read. A result is applied only when its
  // generation and captured device still match the current state.
  property int detailsGeneration: 0
  property string detailsDevice: ""

  // Wi-Fi restart is a two-step operation. The token prevents a stale timer from
  // overriding a newer radio action.
  property int restartToken: 0
  property bool bluetoothBusy: false

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

  property bool restarting: false

  Connections {
    target: NetworkHost

    function onActionFailed(message) { root.actionError = message }
    function onSecretRequested(ssid) {
      root.askingSsid = ssid
      root.expandedSsid = ssid
      root.actionError = ""
    }
  }

  // ---- the parts that keep their own state ----
  //
  // VPN links, DNS, the band, and sharing each keep their own reads and
  // actions. They report failures here, where the panel shows them, and ask for
  // the details to be read again when an action may have changed them.
  NetworkVpn {
    id: vpnState
    onFailed: function (message) { root.actionError = message }
    onChanged: root.refreshDetails()
  }

  NetworkDns {
    id: dnsState
    connected: root.connected
    connection: root.activeConnection
    onFailed: function (message) { root.actionError = message }
    onChanged: root.refreshDetails()
  }

  NetworkBand {
    id: bandState
    connected: root.connected
    device: root.wifiDevice ? root.wifiDevice.name : ""
    ssid: root.activeSsid
    onFailed: function (message) { root.actionError = message }
    onChanged: root.refreshDetails()
  }

  NetworkShare {
    id: shareState
    onFailed: function (message) { root.actionError = message }
  }

  readonly property alias vpns: vpnState.list
  readonly property alias vpnBusy: vpnState.busy
  readonly property alias dnsProviders: dnsState.providers
  readonly property alias dnsBusy: dnsState.busy
  readonly property alias band: bandState.band
  readonly property alias bandOptions: bandState.options
  readonly property alias bandBusy: bandState.busy
  readonly property alias qrVisible: shareState.qrVisible
  readonly property alias qrPath: shareState.qrPath
  readonly property alias qrError: shareState.qrError
  readonly property alias qrReady: shareState.qrReady
  readonly property alias passwordBusy: shareState.passwordBusy
  readonly property alias passwordCopied: shareState.passwordCopied

  // The actions the UI calls. Each clears the last failure first, so a new
  // attempt does not show the previous one's message.
  function toggleVpn(vpn) {
    root.actionError = ""
    vpnState.toggle(vpn)
  }

  function dnsIndex() { return dnsState.index() }

  function setDns(provider) {
    root.actionError = ""
    dnsState.set(provider)
  }

  function bandIndex() { return bandState.index() }

  function setBand(value) {
    root.actionError = ""
    bandState.set(value)
  }

  function bandLabel(item) { return bandState.label(item) }

  function copyPassword() {
    root.actionError = ""
    shareState.copyPassword()
  }

  function setQr(on) { shareState.setQr(on) }

  // What the connection actually is, rather than what it is called.
  property string address: ""
  property string gateway: ""
  property string wired: ""

  function refreshDetails() {
    bandState.refresh()
    vpnState.refresh()

    // Read by device, not by connection: the device is what the panel has, and
    // the answer includes the profile name, which is what the con verbs take.
    // It runs while disconnected too, so an Ethernet cable still shows.
    if (!root.wifiDevice) {
      root.activeConnection = ""
      root.address = ""
      root.gateway = ""
      root.wired = ""
      dnsState.refresh()
      return
    }

    root.detailsGeneration += 1
    root.detailsDevice = root.wifiDevice.name
    details.expectedGeneration = root.detailsGeneration
    details.expectedDevice = root.detailsDevice
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
    property int expectedGeneration: 0
    property string expectedDevice: ""
    command: ["sh", "-c",
      'nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null; echo ---; '
      + 'nmcli -g IP4.ADDRESS device show "$1" 2>/dev/null | head -1; echo ---; '
      + 'nmcli -g IP4.GATEWAY device show "$1" 2>/dev/null | head -1; echo ---; '
      + 'nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null | grep -E "^ethernet:" || true',
      "_", root.wifiDevice ? root.wifiDevice.name : ""]
    stdout: StdioCollector {}
    onExited: function (exitCode) {
      if (root.detailsGeneration !== details.expectedGeneration) return
      if (root.wifiDevice ? root.wifiDevice.name !== details.expectedDevice : details.expectedDevice !== "") return
      if (exitCode !== 0) return

      const parts = String(details.stdout.text || "").split("---")

      // `-g` is terse output and escapes `:` and `\`, so the profile name has
      // to be decoded before it is used as an argument to the con verbs.
      root.activeConnection = Nmcli.decode(String(parts[0] || "").trim())

      root.address = String(parts[1] || "").trim().split("/")[0]
      root.gateway = String(parts[2] || "").trim()

      let wired = ""
      const links = String(parts[3] || "").trim().split("\n")
      for (let i = 0; i < links.length; i++) {
        const fields = links[i].split(":")
        if (fields[1] === "connected") wired = Nmcli.decode(fields[2] || "connected")
      }

      root.wired = wired

      // DNS is a property of the profile, so it can only be read once the
      // profile name is known. Always, not only on a change: a details read
      // can land before the list has named the active network, and that read
      // would otherwise leave DNS empty until the next change.
      dnsState.refresh()
    }
  }

  // refreshDetails reads the profile name and has DNS read once it is known, so
  // DNS is never read against the previous network's name.
  onActiveSsidChanged: {
    root.refreshDetails()
    shareState.reset()
  }

  readonly property int qrSize: Style.space(180)

  // What the empty list means, said in the list rather than in a line below it.
  // Four reasons to be empty and each says which it is, including "there is
  // nothing to connect to because the radio is off" — which was the case that
  // used to render nothing at all, because the list has no height to say it in.
  readonly property string emptyMessage: !root.radioEnabled
    ? "Wireless is off"
    : (root.failed ? "" : (root.scanning ? "Scanning…" : "No networks found"))

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

  function connectSecret(secret, ssid) {
    const target = (ssid && ssid !== "") ? ssid : root.askingSsid
    if (target === "") return

    const item = root.networkFor(target)
    if (!item) return

    root.actionError = ""
    if (secret !== "") {
      root.askingSsid = ""
      NetworkHost.connectWithPsk(item, secret)
    } else {
      root.connect(target)
    }
  }

  function setRadio(on) {
    root.actionError = ""
    NetworkHost.setWifiEnabled(on)

    // Nothing the radio was connected to survives it going off, so neither does
    // the code for that connection.
    if (!on) shareState.reset()
  }

  function setAirplane(on) {
    root.actionError = ""
    root.setRadio(!on)

    if (!root.bluetoothAdapter) {
      root.actionError = "No Bluetooth adapter"
      return
    }

    root.bluetoothBusy = true
    try {
      root.bluetoothAdapter.enabled = !on
    } catch (e) {
      root.actionError = "Could not change Bluetooth"
    }
    root.bluetoothBusy = false
  }

  // Cycling the radio is the fix for the state a network manager occasionally
  // gets stuck in, and doing it from here saves opening a terminal for one
  // command. The delay is the same half second the CLI's own helper uses: long
  // enough for the device to go down, short enough not to feel like a hang.
  function restartWifi() {
    if (root.restarting || !root.radioEnabled) return

    root.actionError = ""
    root.restarting = true
    root.restartToken += 1
    restartOn.token = root.restartToken
    NetworkHost.setWifiEnabled(false)
    restartOn.restart()
  }

  Timer {
    id: restartOn
    interval: 500
    property int token: 0
    onTriggered: {
      if (token !== root.restartToken) return
      if (root.radioEnabled) {
        root.restarting = false
        return
      }
      NetworkHost.setWifiEnabled(true)
      root.restarting = false
    }
  }

  onRadioEnabledChanged: {
    if (root.restarting && root.radioEnabled) {
      restartOn.stop()
      root.restarting = false
      root.restartToken += 1
    }
  }

  Component.onCompleted: {
    shareState.discard()

    NetworkHost.activate()
    root.refreshDetails()
  }

  Component.onDestruction: {
    NetworkHost.deactivate()
    restartOn.stop()
    if (root.restarting) NetworkHost.setWifiEnabled(true)
    root.restarting = false
    shareState.discard()
  }

  // Signal bars: four steps, filled by where the percentage lands.
  function signalLevel(percent) {
    if (percent <= 0) return 0
    if (percent >= 70) return 4
    if (percent >= 45) return 3
    if (percent >= 20) return 2
    return 1
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- connection header ----
    PanelHero {
      width: card.contentWidth
      glyph: Util.wifi
      title: root.connected
        ? root.activeSsid
        : (root.radioEnabled ? "Wi-Fi" : "Wi-Fi disabled")
      subtitle: root.connected
        ? "Connected" + (NetworkHost.signal >= 0 ? " · Signal " + NetworkHost.signal + "%" : "")
          + (NetworkHost.security !== "" ? " · " + NetworkHost.security : "")
        : (root.radioEnabled ? "Not connected" : "Wireless off")
    }

    // Compact, global feedback for the last action. It stays near the header
    // instead of being repeated under every network row.
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

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.failed
      text: "NetworkManager unavailable"
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

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

    PanelActionButton {
      width: card.contentWidth
      visible: root.failed
      label: "Try again"
      navigational: false
      onClicked: root.retry()
    }

    // ---- radios ----
    //
    // Compact toggle-style controls. Airplane mode is visibly both radios, and
    // a missing Bluetooth adapter is reported rather than implied.
    PanelSeparator {}

    Row {
      width: card.contentWidth
      spacing: Style.space(8)

      PanelActionButton {
        width: (card.contentWidth - Style.space(8)) / 2
        label: Util.wifi + "  Wi-Fi"
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
        available: !root.radioBusy && !root.bluetoothBusy
        onClicked: root.setAirplane(!root.airplaneMode)
      }
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: !root.bluetoothAdapter
      text: "No Bluetooth adapter; airplane mode controls Wi-Fi only."
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    // Compact VPN status, even while Advanced is collapsed.
    PanelRow {
      width: card.contentWidth
      visible: root.vpns.some(function (vpn) { return vpn.active })
      label: "VPN"
      controlWidth: 0
      hasControl: false
      value: {
        for (let i = 0; i < root.vpns.length; i++) {
          if (root.vpns[i].active) {
            const name = root.vpns[i].name || ""
            return name.length > 20 ? name.substring(0, 17) + "…" : name + " connected"
          }
        }
        return "None"
      }
    }

    PanelSeparator {}

    // ---- networks ----
    PanelSectionHeader {
      width: card.contentWidth
      label: "Wi-Fi Networks"
      action: root.scanning ? "Scanning…" : "Rescan"
      actionEnabled: root.radioEnabled && !root.scanning && !root.failed && !root.busy
      onActionTriggered: root.rescan()
    }

    // Reserve a minimum height for the list area so an empty or freshly
    // scanned list does not collapse the panel and reflow everything below it.
    Item {
      id: networksArea
      width: card.contentWidth
      implicitHeight: Math.max(Style.space(84), root.networks.length === 0
        ? (emptyMessageText.implicitHeight + Style.space(8))
        : networksColumn.implicitHeight)
      clip: true

      Text {
        id: emptyMessageText
        anchors.centerIn: parent
        width: parent.width
        visible: root.networks.length === 0 && root.emptyMessage !== ""
        text: root.emptyMessage
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }

      Column {
        id: networksColumn
        width: parent.width
        anchors.top: parent.top
        spacing: Style.space(2)
        visible: root.networks.length > 0

        Repeater {
          model: root.networks

        delegate: Column {
          id: netRow
          required property var modelData

          readonly property bool inFlight: root.actionSsid === netRow.modelData.ssid && root.busy
          readonly property bool expanded: root.expandedSsid === netRow.modelData.ssid
          readonly property var network: netRow.modelData.network
          property bool passwordVisible: false

          width: card.contentWidth
          spacing: Style.space(2)

          ChoiceRow {
            width: parent.width
            height: Style.space(26)
            available: root.radioEnabled && !root.busy
            clip: true

            glyph: netRow.modelData.secured ? Util.lock : ""
            label: netRow.inFlight
              ? (root.actionKind === "connect" ? "Connecting…" : "Disconnecting…")
              : netRow.modelData.ssid
            selected: netRow.modelData.inUse && !netRow.inFlight

            onClicked: root.expandedSsid = netRow.expanded ? "" : netRow.modelData.ssid

            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: root.bandLabel(netRow.modelData)
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }

              Row {
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                  model: 4
                  delegate: Rectangle {
                    required property int index
                    width: 2
                    height: 3 + index * 2
                    radius: 1
                    anchors.bottom: parent.bottom
                    color: index < root.signalLevel(netRow.modelData.signal)
                      ? (netRow.modelData.inUse ? Theme.accent : Theme.muted)
                      : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
                  }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                text: netRow.expanded ? "⌄" : "›"
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }
          }

          Item {
            width: parent.width
            // Animate the open/close instead of snapping, so the panel grows
            // smoothly rather than jumping.
            implicitHeight: netRow.expanded ? innerExpanded.implicitHeight : 0
            clip: true
            opacity: netRow.expanded ? 1 : 0
            enabled: netRow.expanded
            Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic } }

            Column {
              id: innerExpanded
              width: parent.width
              spacing: Style.space(6)

            // Password form for secured, unused networks.
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: netRow.modelData.secured && !netRow.modelData.inUse

              onVisibleChanged: {
                if (!visible) return
                inlineSecretField.text = ""
                Qt.callLater(function () {
                  if (inlineSecretField.visible && inlineSecretField.parent)
                    inlineSecretField.forceActiveFocus()
                })
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

              Row {
                width: parent.width
                spacing: Style.space(4)

                TextField {
                  id: inlineSecretField
                  width: Math.max(0, parent.width - showPasswordButton.width - Style.space(4))
                  echoMode: netRow.passwordVisible ? TextInput.Normal : TextInput.Password
                  placeholderText: "network password"
                  Keys.onEscapePressed: {
                    inlineSecretField.text = ""
                    root.askingSsid = ""
                  }
                  onAccepted: {
                    const secret = inlineSecretField.text
                    inlineSecretField.text = ""
                    root.connectSecret(secret, netRow.modelData.ssid)
                  }
                }

                TextButton {
                  id: showPasswordButton
                  label: netRow.passwordVisible ? "Hide" : "Show"
                  available: true
                  onClicked: netRow.passwordVisible = !netRow.passwordVisible
                }
              }

              PanelActionButton {
                width: parent.width
                label: "Connect"
                navigational: false
                available: !root.busy && root.actionSsid === "" && inlineSecretField.text !== ""
                onClicked: {
                  const secret = inlineSecretField.text
                  inlineSecretField.text = ""
                  root.connectSecret(secret, netRow.modelData.ssid)
                }
              }

              PanelActionButton {
                width: parent.width
                label: "Cancel"
                navigational: false
                onClicked: {
                  inlineSecretField.text = ""
                  root.askingSsid = ""
                }
              }
            }

            // Simple connect action for open networks.
            PanelActionButton {
              width: parent.width
              visible: !netRow.modelData.secured && !netRow.modelData.inUse
              label: "Connect"
              navigational: false
              available: !root.busy && root.actionSsid === ""
              onClicked: root.connect(netRow.modelData.ssid)
            }

            // Active network action.
            PanelActionButton {
              width: parent.width
              visible: netRow.modelData.inUse
              label: "Disconnect"
              navigational: false
              available: !root.busy && root.actionSsid === ""
              onClicked: {
                root.expandedSsid = ""
                root.disconnect(netRow.modelData.ssid)
              }
            }

            // Known-network actions.
            Row {
              width: parent.width
              spacing: Style.space(4)
              visible: netRow.network ? netRow.network.known : false

              TextButton {
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
                label: "Auto: " + (netRow.network && netRow.network.autoconnect ? "On" : "Off")
                active: !!(netRow.network && netRow.network.autoconnect)
                available: !root.busy
                onClicked: {
                  if (netRow.network) netRow.network.autoconnect = !netRow.network.autoconnect
                }
              }
            }

            Text {
              width: parent.width
              visible: root.actionError !== "" && netRow.expanded
              text: root.actionError
              color: Theme.danger
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
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
    }
    }

    PanelSeparator {}

    // ---- advanced ----
    PanelActionButton {
      width: card.contentWidth
      label: "Advanced"
      value: root.moreExpanded ? "hide" : "show"
      navigational: false
      onClicked: root.moreExpanded = !root.moreExpanded
    }

    Item {
      width: card.contentWidth
      // Animate the open/close instead of snapping.
      implicitHeight: root.moreExpanded ? innerAdvanced.implicitHeight : 0
      clip: true
      opacity: root.moreExpanded ? 1 : 0
      enabled: root.moreExpanded
      Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic } }

      Column {
        id: innerAdvanced
        width: parent.width
        spacing: Style.space(8)

      // Connection details
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

      // Sharing
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

      Item {
        width: parent.width
        // Reserve the QR slot while it loads so the panel does not reflow
        // when the image becomes ready.
        height: root.qrVisible ? root.qrSize : 0
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

      PanelSeparator {}

      // VPNs
      PanelSectionHeader {
        width: parent.width
        label: "VPNs & Proxies"
      }

      Text {
        width: parent.width
        height: implicitHeight
        visible: root.vpns.length === 0
        text: "None"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.vpns

          delegate: PanelActionButton {
            required property var modelData

            width: parent.width
            label: (modelData.name.length > 18 ? modelData.name.substring(0, 15) + "…" : modelData.name) + " (" + modelData.type + ")"
            value: (modelData.active ? "Connected" : "Disconnected")
              + " · " + (modelData.active ? "disc" : "conn")
            navigational: false
            available: !root.vpnBusy
            onClicked: root.toggleVpn(modelData)
          }
        }
      }

      PanelSeparator {}

      // Restart and forget
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
}
