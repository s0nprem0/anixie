import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Wi-Fi panel: the radio, what is in use, what is nearby, and a way to switch.
//
// Reads and actions come from Quickshell.Networking, which talks to
// NetworkManager over D-Bus. nmcli is kept for the few facts the service does
// not expose: the profile name for DNS, the gateway, VPN links, and the QR.
//
// The shape follows the reference's panels: a hero row for the thing the panel is
// *about* (the radio), then sections under a rule and a heading. The sections are
// what make a panel of this size readable — a flat run of rows leaves you
// counting rather than scanning — and the hero is the one control worth reaching
// for without aiming.
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

  // ---- DNS ----
  //
  // Per connection, not global: nmcli keeps it on the connection profile, which
  // is why it follows the network rather than the machine. An empty list means
  // "whatever the router hands out", and that is a choice worth offering by name
  // — the alternative is a panel that can only ever add a resolver, never go
  // back to the one DHCP gave you.
  readonly property var dnsProviders: [
    { label: "Automatic", value: "" },
    { label: "Cloudflare", value: "1.1.1.1 1.0.0.1" },
    { label: "Quad9", value: "9.9.9.9 149.112.112.112" },
    { label: "Google", value: "8.8.8.8 8.8.4.4" }
  ]

  property string dns: ""
  property bool dnsBusy: false

  // What the connection actually is, rather than what it is called.
  property string address: ""
  property string gateway: ""
  property string wired: ""
  property string vpn: ""

  function refreshDetails() {
    // Read by device, not by connection: the device is what the panel has, and
    // the answer includes the profile name, which is what the con verbs take.
    // It runs while disconnected too, so an Ethernet cable or VPN still shows.
    if (!root.wifiDevice) {
      root.activeConnection = ""
      root.address = ""
      root.gateway = ""
      root.wired = ""
      root.vpn = ""
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
      + 'nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null | grep -E "^(ethernet|wireguard|tun|vpn):" || true',
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
        let vpn = ""
        const links = String(parts[3] || "").trim().split("\n")
        for (let i = 0; i < links.length; i++) {
          const fields = links[i].split(":")
          if (fields[1] !== "connected") continue
          if (fields[0] === "ethernet") wired = root.decodeSsid(fields[2] || "connected")
          if (fields[0] === "wireguard" || fields[0] === "tun" || fields[0] === "vpn") {
            vpn = root.decodeSsid(fields[2] || fields[0])
          }
        }

        root.wired = wired
        root.vpn = vpn

        // DNS is a property of the profile, so it can only be read once the
        // profile name is known. Always, not only on a change: a details read
        // can land before the list has named the active network, and that read
        // would otherwise leave DNS empty until the next change.
        root.refreshDns()
      }
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
    for (let i = 0; i < root.dnsProviders.length; i++) {
      if (root.dnsKey(root.dnsProviders[i].value) === current) return i
    }
    return -1
  }

  function refreshDns() {
    const connection = root.activeConnection
    if (!root.connected || connection === "") {
      root.dns = ""
      return
    }

    dnsGet.command = ["sh", "-c",
      'nmcli -g ipv4.dns con show "$1" 2>/dev/null || true', "_", connection]
    dnsGet.running = false
    dnsGet.running = true
  }

  function setDns(value) {
    const connection = root.activeConnection
    if (connection === "") return

    root.actionError = ""
    root.dnsBusy = true
    dnsSet.command = ["sh", "-c",
      'nmcli con mod "$1" ipv4.dns "$2" ipv4.ignore-auto-dns "$3" >/dev/null && nmcli con up "$1" >/dev/null',
      "_", connection, value, value === "" ? "no" : "yes"]
    dnsSet.running = true
  }

  Process {
    id: dnsGet
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.dns = String(this.text).trim().split("\n")[0].trim()
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
    command: ["wifi-qr"]
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

  // Signal bars: four steps, filled by where the percentage lands.
  function signalLevel(percent) {
    if (percent >= 70) return 4
    if (percent >= 45) return 3
    if (percent >= 20) return 2
    return 1
  }

  // A cap on the list's height, so a crowded street does not push the rest of the
  // panel off the screen. The panel itself scrolls; this is what keeps the list
  // from swallowing the whole of it, and the two scroll together rather than one
  // inside the other.
  readonly property int maxListHeight: Style.space(220)

  // Tall enough to say something in when there is nothing to list.
  readonly property int emptyListHeight: Style.space(32)

  // A row and the gap after it. The list's height is built from these rather than
  // from the cap, so it ends on a whole row: a 220px cap used to cut the eighth
  // network in half, which reads as a rendering fault rather than as "there is
  // more below".
  readonly property int rowHeight: Style.space(26)
  readonly property int rowGap: Style.space(2)
  readonly property int rowStep: root.rowHeight + root.rowGap
  readonly property int visibleRows: Math.max(1, Math.floor((root.maxListHeight + root.rowGap) / root.rowStep))

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    // ---- the radio ----
    //
    // The one control worth reaching for without aiming, so it is in the hero
    // where the glyph you clicked this panel by leads the eye.
    PanelHero {
      width: card.contentWidth
      glyph: Util.wifi
      title: "Wi-Fi"
      subtitle: root.connected ? root.activeSsid : (root.radioEnabled ? "not connected" : "wireless off")
      controlWidth: radioSwitch.implicitWidth

      ToggleSwitch {
        id: radioSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: root.radioEnabled
        busy: root.radioBusy
        onToggled: root.setRadio(!root.radioEnabled)
      }
    }

    // The last action's own failure — a connect, a DNS change, a forgotten
    // profile — next to the thing it happened to. The list's "Unavailable"
    // below is for the read, not for these.
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

    PanelSeparator {
      visible: root.connected
    }

    // ---- what is in use ----
    PanelSectionHeader {
      width: card.contentWidth
      visible: root.connected
      label: "Connection"
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

    PanelActionButton {
      id: disconnectButton
      width: card.contentWidth
      visible: root.connected && !root.failed
      label: root.busy && root.actionKind === "disconnect" ? "Disconnecting…" : "Disconnect"
      danger: true
      outlined: true
      navigational: false
      available: !root.busy
      onClicked: root.disconnect(root.activeSsid)
    }

    PanelRow {
      id: dnsRow
      width: card.contentWidth
      visible: root.connected
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
        onActivated: function (index) { root.setDns(root.dnsProviders[index].value) }
      }
    }

    PanelRow {
      width: card.contentWidth
      visible: root.connected && root.address !== ""
      label: "Address"
      value: root.address
    }

    PanelRow {
      width: card.contentWidth
      visible: root.connected && root.gateway !== ""
      label: "Gateway"
      value: root.gateway
    }

    // The links the Wi-Fi panel is not about, but is the only network surface the
    // shell has: an Ethernet cable on a dock and a VPN that is up both change the
    // answer to "is this machine online".
    PanelRow {
      width: card.contentWidth
      visible: root.wired !== ""
      label: "Wired"
      value: root.wired
    }

    PanelRow {
      width: card.contentWidth
      visible: root.vpn !== ""
      label: "VPN"
      value: root.vpn
    }

    PanelActionButton {
      width: card.contentWidth
      visible: root.connected
      label: "Forget this network"
      danger: true
      navigational: false
      onClicked: root.forget()
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

    // ---- what is nearby ----
    //
    // The rescan belongs to the list it rescans: at the end of the heading rather
    // than in a row of its own at the bottom, which read as a label and put the
    // one control for the list a screenful away from the list.
    PanelSectionHeader {
      width: card.contentWidth
      label: "Networks"
      action: root.scanning ? "Scanning…" : "Rescan"
      actionEnabled: root.radioEnabled && !root.scanning && !root.failed && !root.busy
      onActionTriggered: root.rescan()
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(6)
      visible: root.askingSsid !== ""

      onVisibleChanged: {
        if (!visible) return
        secretField.text = ""
        Qt.callLater(function () { secretField.forceActiveFocus() })
      }

      Text {
        width: parent.width
        text: "Password for " + root.askingSsid
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      TextField {
        id: secretField
        width: parent.width
        echoMode: TextInput.Password
        placeholderText: "network password"
        Keys.onEscapePressed: root.askingSsid = ""
        onAccepted: root.connectSecret(secretField.text)
      }

      PanelActionButton {
        width: parent.width
        label: "Connect"
        navigational: false
        available: secretField.text !== ""
        onClicked: root.connectSecret(secretField.text)
      }

      PanelActionButton {
        width: parent.width
        label: "Cancel"
        navigational: false
        onClicked: root.askingSsid = ""
      }

      PanelSeparator {}
    }

    ListView {
      id: list
      width: card.contentWidth
      // Whole rows only: `visibleRows` rows and the gaps between them, capped.
      height: Math.max(
        count > 0 ? Math.min(count, root.visibleRows) * root.rowStep - root.rowGap : 0,
        root.emptyMessage !== "" ? root.emptyListHeight : 0)
      clip: true
      model: root.networks
      spacing: root.rowGap
      rightMargin: Style.space(8)
      boundsBehavior: Flickable.StopAtBounds

      // Visible while it can scroll, rather than only while it is being used:
      // eight networks behind a list that looks like it ends is a list you do not
      // know to scroll.
      ScrollBar.vertical: ScrollBar {
        policy: list.contentHeight > list.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
      }

      delegate: ChoiceRow {
        id: rowItem
        required property var modelData

        readonly property bool inFlight: root.actionSsid === rowItem.modelData.ssid && root.busy

        width: list.width - list.rightMargin
        height: root.rowHeight
        available: root.radioEnabled && !root.busy

        // Only for networks that need a key. An open network gets no glyph rather
        // than an open padlock: the absence says "open" more quietly than a
        // symbol repeated on every row would.
        glyph: rowItem.modelData.secured ? Util.lock : ""
        label: rowItem.inFlight
          // The row says what it is doing while it does it. Without this a click
          // on a network that takes a second looks like nothing happened.
          ? (root.actionKind === "connect" ? "Connecting…" : "Disconnecting…")
          : rowItem.modelData.ssid
        selected: rowItem.modelData.inUse && !rowItem.inFlight
        onClicked: {
          if (rowItem.modelData.inUse) root.disconnect(rowItem.modelData.ssid)
          else root.connect(rowItem.modelData.ssid)
        }

        // Four ascending bars, the filled count set by the signal percentage.
        Row {
          spacing: 2

          Repeater {
            model: 4
            delegate: Rectangle {
              required property int index
              width: 3
              height: 4 + index * 3
              radius: Theme.cornerRadius
              // Standing on the same line, not floating around their own middles:
              // centre-aligned bars of four different heights read as dashes, not
              // as a staircase, which is the whole point of the glyph.
              anchors.bottom: parent.bottom
              color: index < root.signalLevel(rowItem.modelData.signal)
                ? (rowItem.selected ? Theme.accent : Theme.muted)
                : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
            }
          }
        }
      }

      // What an empty list means, rather than an empty box. Said in here,
      // where the entries would have been.
      Text {
        anchors.fill: parent
        visible: list.count === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: root.emptyMessage
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    // The QR, behind a toggle. It carries the network's password in the clear, so
    // it is drawn only while this is on, and generated only then — the image is
    // not sitting in the state directory waiting for a panel to be open.
    PanelSeparator {
      visible: root.connected
    }

    Toggle {
      id: qrToggle
      width: card.contentWidth
      visible: root.connected
      height: implicitHeight
      label: "Share this network"
      description: "a QR code another device can scan to join"
      checked: root.qrVisible
      onToggled: root.setQr(!root.qrVisible)
    }

    // The box is the size the code is drawn at, not the size of the file behind
    // it: an Image's implicit height is the source's own, and a QR that arrives
    // as 512px made a 512px row that the panel then had to cut.
    Item {
      width: card.contentWidth
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
      width: card.contentWidth
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
}