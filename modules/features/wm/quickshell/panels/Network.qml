import QtQuick
import QtQuick.Controls
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// Wi-Fi panel: the radio, what is in use, what is nearby, and a way to switch.
//
// nmcli is the only network manager here, so this is shell-driven rather than
// backed by a native module the way audio and power are.
//
// The shape follows the reference's panels: a hero row for the thing the panel is
// *about* (the radio), then sections under a rule and a heading. The sections are
// what make a panel of this size readable — a flat run of rows leaves you
// counting rather than scanning — and the hero is the one control worth reaching
// for without aiming.
Item {
  id: root

  property var wifiDevice: ""
  property var networks: []
  property string activeSsid: ""

  // The NetworkManager profile behind the SSID. The two are not the same: a
  // profile can be renamed, and every nmcli con verb (show, mod, delete, up)
  // takes the profile name, not the SSID. Reading it from the device keeps the
  // panel from acting on a connection it merely thinks is there.
  property string activeConnection: ""

  property bool scanning: false

  // nmcli exiting non-zero is not the same as there being no networks, and the
  // panel says which it is rather than showing an empty list either way.
  property bool failed: false
  property string failure: ""

  // The radio. Read from nmcli rather than assumed, and written optimistically:
  // the switch answers the click at once and the read-back confirms it, because
  // `nmcli radio` takes a moment and a switch that lags its own click reads as
  // broken.
  property bool radioEnabled: true
  property bool radioBusy: false

  // The row whose action is running, and which action it is. The row renders
  // "Connecting…" / "Disconnecting…" so a click that takes a second is visibly
  // doing something rather than looking ignored.
  property string actionSsid: ""
  property string actionKind: ""

  // The first line of the last action's failure. A connect that fails for any
  // reason other than a missing secret used to look exactly like one that
  // needed a password; this is where the difference is said out loud.
  property string actionError: ""

  // True while an action is settling. The fast poll runs for the action and
  // stops after it; restarting the timer directly removed its `running`
  // binding and left it polling every 900ms for the rest of the panel's life.
  property bool settling: false

  // A secured network that would not join because it has no stored key. The
  // panel asks here rather than failing silently: NetworkManager wants secrets
  // through a secret agent, and this shell is not one.
  property string askingSsid: ""

  // One action at a time. Two connects racing each other is not a faster connect,
  // it is two nmcli processes fighting over the device and neither result
  // trustworthy.
  readonly property bool busy: root.actionKind !== ""

  // ---- share by QR ----
  //
  // The QR holds the network password, so it is off by default, generated only
  // when switched on, and the file it draws is removed again when it is switched
  // off. `qrPath` is what SizedImage is given and only set once a file exists.
  property bool qrVisible: false
  property string qrPath: ""
  property string qrError: ""
  readonly property bool qrReady: root.qrPath !== ""

  // A bool, and it has to be one. Declared as a string this held the *text*
  // "false" when there was no connection, which is truthy as far as every test
  // of it is concerned — so the QR toggle was offered for a network the panel
  // had just said was unavailable, and the hero's subtitle was empty rather than
  // naming the state.
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
    if (root.wifiDevice === "") {
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
    // The profile name, not the SSID: a renamed profile has a different one,
    // and deleting by the wrong name either fails or deletes nothing.
    const connection = root.activeConnection
    if (!root.connected || connection === "") return

    root.actionError = ""
    forgetProc.command = ["nmcli", "connection", "delete", connection]
    forgetProc.running = true
  }

  // The network row for an SSID, for deciding whether a failed connect could
  // have been a missing key.
  function networkFor(ssid) {
    for (let i = 0; i < root.networks.length; i++) {
      if (root.networks[i].ssid === ssid) return root.networks[i]
    }
    return null
  }

  // One read for the facts the panel did not have: the profile name, the
  // address, the other links that are up, and the VPN. The fields are asked for
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
      "_", root.wifiDevice]
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

  Process {
    id: forgetProc
    running: false
    stderr: StdioCollector { id: forgetErr }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.activeSsid = ""
        root.activeConnection = ""
        root.dns = ""
        root.actionError = ""
      } else {
        const message = String(forgetErr.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not forget this network"
      }

      root.refresh()
      root.refreshDns()
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
      root.refresh()
    }
  }

  // refreshDetails reads the profile name and calls this once it is known, so
  // DNS is never read against the previous network's name.
  onActiveSsidChanged: root.refreshDetails()

  readonly property int qrSize: Style.space(180)

  readonly property bool connected: root.activeSsid !== ""

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

  // A scan reports networks the device has not seen yet; connecting to a hidden
  // network is out of scope, so only listed ones are offered.
  function parse(raw) {
    const found = []

    for (let i = 0; i < raw.split("\n").length; i++) {
      const row = raw.split("\n")[i]
      if (row === "") continue

      const parts = row.split(":")

      // IN-USE,SSID,SIGNAL,SECURITY. The SSID is whatever sits between the
      // first and the last two fields, rejoined, because nmcli escapes a colon
      // inside an SSID as "\:" and a naive split would tear it in half.
      if (parts.length < 4) continue

      const inUse = parts[0] === "*"
      const ssid = decodeSsid(parts.slice(1, parts.length - 2).join(":"))
      if (ssid === "") continue

      // nmcli reports an open network as "--"; anything else is some form of key
      // or 802.1X, and the row only has to say "this one is not open".
      const security = decodeSsid(parts[parts.length - 1])

      found.push({
        ssid: ssid,
        signal: parseInt(parts[parts.length - 2], 10) || 0,
        security: security,
        secured: security !== "" && security !== "--",
        inUse: inUse
      })
    }

    // One row per access point, so a network broadcast by two radios — the 2.4
    // and the 5 GHz of the same name — is listed twice, and two identical rows
    // that do the same thing is not a list to choose from. The one in use wins
    // over the stronger of the pair; otherwise the stronger one does, and the
    // pair counts as secured if either half is.
    const byName = {}

    for (const network of found) {
      const seen = byName[network.ssid]

      if (!seen) {
        byName[network.ssid] = network
        continue
      }

      const takesIt = (network.inUse && !seen.inUse)
        || (network.inUse === seen.inUse && network.signal > seen.signal)

      const winner = takesIt ? network : seen
      winner.secured = winner.secured || seen.secured
      byName[network.ssid] = winner
    }

    const unique = Object.keys(byName).map(function (name) { return byName[name] })

    // Strongest first, with the network in use pinned to the top.
    unique.sort(function (a, b) {
      if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
      return b.signal - a.signal
    })

    return unique
  }

  function decodeSsid(value) {
    return String(value).replace(/\\(.)/g, "$1")
  }

  // ---- commands ----

  // `--rescan no` is what makes this a status query. The default policy
  // rescans when NetworkManager's cache is stale, so the ten-second poll was
  // quietly starting real radio scans — the cost the bar's Wifi readout moved
  // to D-Bus to avoid. The explicit Rescan button is the one that rescans.
  Process {
    id: listProc
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = root.parse(this.text)
        root.networks = found
        const wasSsid = root.activeSsid
        root.activeSsid = found.length && found[0].inUse ? found[0].ssid : ""

        // A code for one network is not a code for another. When the network
        // changes while the QR is up, take it away rather than leave a phone
        // pointed at the wrong credentials. Only on a change, not on every poll —
        // the scan runs periodically and would switch it off each time otherwise.
        if (root.qrVisible && root.activeSsid !== wasSsid) root.setQr(false)

        // The process that starts as part of building the shell can come back
        // with its output already dropped, which reads as "no networks". Ask
        // again rather than showing an empty list.
        if (found.length === 0 && root.emptyRetries < 3) {
          root.emptyRetries += 1
          emptyRetry.restart()
        }
      }
    }

    stderr: StdioCollector {
      onStreamFinished: root.failure = this.text.trim()
    }

    onExited: function (exitCode) {
      // A successful read is a successful read whether or not it found anything.
      if (exitCode === 0) {
        root.failed = false
        root.failure = ""
        return
      }

      // The radio being off is not a failure: nmcli says so by exiting non-zero,
      // and the list already says "Wireless is off". Painting the panel red for
      // it made a switch look like a fault.
      if (!root.radioEnabled) {
        root.failed = false
        root.failure = ""
        return
      }

      root.failed = true
      if (root.failure === "") root.failure = "nmcli exited with " + exitCode

      // Nothing that was read before the failure can still be true. Saying
      // "Unavailable" while a connection, an address, a DNS choice and a QR
      // code for them are all still on screen is worse than saying nothing.
      root.activeSsid = ""
      root.activeConnection = ""
      root.networks = []
      root.address = ""
      root.gateway = ""
      root.wired = ""
      root.vpn = ""
      root.dns = ""
      if (root.qrVisible) root.setQr(false)

      // NetworkManager is still coming up on the first open of a session, and a
      // failure that fixes itself in a second should not sit there for ten. The
      // same budget as an empty list: three quick retries, then the slow poll.
      if (root.emptyRetries < 3) {
        root.emptyRetries += 1
        emptyRetry.restart()
      }
    }
  }

  property int emptyRetries: 0

  Timer {
    id: emptyRetry
    interval: 700
    onTriggered: root.refresh()
  }

  Process {
    id: scanProc
    running: false
    stderr: StdioCollector { id: scanErr }
    onExited: function (exitCode) {
      if (exitCode === 0) return

      const message = String(scanErr.text || "").trim().split("\n")[0]

      // "Scanning not allowed immediately following previous scan" is not a
      // failure: the scan already in progress is the one the poll is waiting
      // for, so leave `scanning` set and let it finish.
      if (/scanning not allowed/i.test(message)) return

      root.scanning = false
      scanTimeout.stop()
      root.actionError = message !== "" ? message : "Could not scan for networks"
    }
  }

  Process {
    id: actionProc
    running: false
    stderr: StdioCollector { id: actionErr }
    onExited: function (exitCode) {
      const kind = root.actionKind
      const ssid = root.actionSsid
      const message = String(actionErr.text || "").trim().split("\n")[0]

      // Cleared on exit rather than on the re-read, so a failed connect still
      // takes the row out of its "Connecting…" state instead of leaving it there.
      root.actionSsid = ""
      root.actionKind = ""
      root.settling = false

      if (exitCode !== 0) {
        // A secret that NetworkManager wanted is a password prompt; anything
        // else — out of range, device busy, polkit denied — is said out loud
        // rather than dressed up as a password problem.
        const net = root.networkFor(ssid)
        const secret = /secrets were required|no secrets|password|802-11-wireless-security/i.test(message)
        const askAnyway = message === "" && net !== null && net.secured

        if (kind === "connect" && (secret || askAnyway)) {
          root.askingSsid = ssid
          root.actionError = "Could not join " + ssid + ". Check the password."
        } else {
          root.actionError = message !== ""
            ? message
            : "Could not " + (kind === "disconnect" ? "disconnect" : "connect")
        }
      }

      root.refresh()
    }
  }

  Process {
    id: deviceProc
    running: true
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE", "device", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const rows = this.text.split("\n")
        for (let i = 0; i < rows.length; i++) {
          const parts = rows[i].split(":")
          if (parts[1] === "wifi") root.wifiDevice = parts[0]
        }

        // The device name is what every read below keys on; ask once it is known.
        if (root.wifiDevice !== "") root.refreshDetails()
      }
    }
  }

  Process {
    id: radioGet
    running: true
    command: ["nmcli", "-t", "radio", "wifi"]
    stdout: StdioCollector {
      onStreamFinished: {
        // Read-back confirms the optimistic value, and is also what tells the
        // panel on first open that the radio is already off.
        root.radioEnabled = this.text.trim() === "enabled"
      }
    }
  }

  Process {
    id: radioSet
    running: false
    stderr: StdioCollector { id: radioErr }
    onExited: function (exitCode) {
      root.radioBusy = false
      if (exitCode !== 0) {
        const message = String(radioErr.text || "").trim().split("\n")[0]
        root.actionError = message !== "" ? message : "Could not change the radio"
      }
      // Read the radio back either way: a failed write leaves the optimistic
      // value wrong, and a switch should show what is, not what was asked.
      radioGet.running = false
      radioGet.running = true
      root.refresh()
    }
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  // Ask again after a failure. The flag is cleared first so the panel stops
  // treating the last failure as the current state, and put back by the read
  // that follows if the failure was not transient after all.
  function retry() {
    root.failed = false
    root.failure = ""
    root.actionError = ""
    root.emptyRetries = 0
    root.refresh()
  }

  function rescan() {
    if (!root.radioEnabled) return

    root.actionError = ""
    root.scanning = true
    scanProc.command = ["nmcli", "device", "wifi", "rescan"]
    scanProc.running = true

    // Keep the list refreshing for the few seconds a scan takes. The first
    // reply after `rescan` can still be the pre-scan cache, so clearing
    // `scanning` when it arrives stopped the poll before the new results.
    scanTimeout.restart()
  }

  function connect(ssid) {
    if (ssid === "" || !root.radioEnabled) return

    root.actionError = ""
    root.actionSsid = ssid
    root.actionKind = "connect"
    root.settling = true
    actionProc.command = ["nmcli", "device", "wifi", "connect", ssid]
    actionProc.running = true
  }

  function disconnect(ssid) {
    if (root.wifiDevice === "") return

    root.actionError = ""
    root.actionSsid = ssid
    root.actionKind = "disconnect"
    root.settling = true
    actionProc.command = ["nmcli", "device", "disconnect", root.wifiDevice]
    actionProc.running = true
  }

  // The secret goes on the command line, which is visible in the process list
  // for the moment nmcli runs. That is the price of not being a secret agent;
  // the alternative is a D-Bus agent and a keyring.
  function connectSecret(secret) {
    if (root.askingSsid === "" || secret === "") return

    const ssid = root.askingSsid
    root.askingSsid = ""
    root.actionError = ""
    root.actionSsid = ssid
    root.actionKind = "connect"
    root.settling = true
    actionProc.command = ["nmcli", "device", "wifi", "connect", ssid, "password", secret]
    actionProc.running = true
  }

  function setRadio(on) {
    root.actionError = ""
    root.radioBusy = true
    root.radioEnabled = on

    // Nothing the radio was connected to survives it going off, so neither does
    // the claim to be connected, or the code for that connection.
    if (!on) {
      root.activeSsid = ""
      if (root.qrVisible) root.setQr(false)
    }

    radioSet.command = ["nmcli", "radio", "wifi", on ? "on" : "off"]
    radioSet.running = true
  }

  // The fast poll, for a scan or an action that is still in flight. Bound to
  // both flags rather than restarted: `restart()` assigns `running`, which
  // removes the binding and leaves the timer on forever.
  Timer {
    id: settle
    interval: 900
    repeat: true
    running: root.scanning || root.settling
    onTriggered: root.refresh()
  }

  Timer {
    id: scanTimeout
    interval: 5000
    repeat: false
    onTriggered: root.scanning = false
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    // A code from a previous run is a password left behind; the toggle that
    // made it is off in this fresh panel.
    if (root.stateDir !== "") rmQr.running = true

    deviceProc.running = false
    deviceProc.running = true
    radioGet.running = false
    radioGet.running = true
    root.emptyRetries = 0
    root.failed = false
    root.refresh()
  }

  Component.onDestruction: {
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