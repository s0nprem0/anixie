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
  readonly property bool qrReady: root.qrPath !== ""

  // A bool, and it has to be one. Declared as a string this held the *text*
  // "false" when there was no connection, which is truthy as far as every test
  // of it is concerned — so the QR toggle was offered for a network the panel
  // had just said was unavailable, and the hero's subtitle was empty rather than
  // naming the state.
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
      qrQuery.running = false
      qrQuery.running = true
    } else {
      root.qrPath = ""
      // Take the image away with the toggle. Leaving a password-bearing QR in the
      // state directory after the switch that put it there is off is the kind of
      // thing nobody remembers to clean up.
      rmQr.running = true
    }
  }

  Process {
    id: qrQuery
    command: ["wifi-qr"]
    stdout: StdioCollector {
      onStreamFinished: root.qrPath = String(this.text || "").trim()
    }
  }

  Process {
    id: rmQr
    command: ["sh", "-c", 'rm -f "$1"', "_", root.stateDir + "/wifi-qr.png"]
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/anixie"

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

      found.push({
        ssid: ssid,
        signal: parseInt(parts[parts.length - 2], 10) || 0,
        security: decodeSsid(parts[parts.length - 1]),
        inUse: inUse
      })
    }

    // Strongest first, with the network in use pinned to the top.
    found.sort(function (a, b) {
      if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
      return b.signal - a.signal
    })

    return found
  }

  function decodeSsid(value) {
    return String(value).replace(/\\(.)/g, "$1")
  }

  // nmcli reports an open network as "--"; anything else is some form of key or
  // 802.1X, and the row only has to say "this one is not open".
  function secured(network) {
    const s = String(network.security || "")
    return s !== "" && s !== "--"
  }

  // ---- commands ----

  Process {
    id: listProc
    running: true
    command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
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
        root.scanning = false

        if (found.length > 0) {
          root.failed = false
          root.failure = ""
        }

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
      if (exitCode !== 0) {
        root.failed = true
        if (root.failure === "") root.failure = "nmcli exited with " + exitCode

        // Nothing that was read before the failure can still be true. Saying
        // "Unavailable" while a connection, a password and a QR code for it are
        // all still on screen is worse than saying nothing at all.
        root.activeSsid = ""
        if (root.qrVisible) root.setQr(false)
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
  }

  Process {
    id: actionProc
    running: false
    stdout: StdioCollector {
      // Whether it worked shows up in the list a moment later; re-read now so
      // the panel settles quickly either way.
      onStreamFinished: root.refresh()
    }
    onExited: function () {
      // Cleared on exit rather than on the re-read, so a failed connect still
      // takes the row out of its "Connecting…" state instead of leaving it there.
      root.actionSsid = ""
      root.actionKind = ""
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
    onExited: function () {
      root.radioBusy = false
      radioGet.running = false
      radioGet.running = true
      root.refresh()
    }
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function rescan() {
    root.scanning = true
    scanProc.command = ["nmcli", "device", "wifi", "rescan"]
    scanProc.running = true

    // A rescan takes a moment to report; poll a little harder while it runs.
    settle.restart()
  }

  function connect(ssid) {
    root.actionSsid = ssid
    root.actionKind = "connect"
    actionProc.command = ["nmcli", "device", "wifi", "connect", ssid]
    actionProc.running = true
    settle.restart()
  }

  function disconnect(ssid) {
    root.actionSsid = ssid
    root.actionKind = "disconnect"
    actionProc.command = ["nmcli", "device", "disconnect", root.wifiDevice]
    actionProc.running = true
    settle.restart()
  }

  function setRadio(on) {
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

  Timer {
    id: settle
    interval: 900
    repeat: true
    running: root.scanning
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    deviceProc.running = false
    deviceProc.running = true
    radioGet.running = false
    radioGet.running = true
    root.emptyRetries = 0
    root.failed = false
    root.refresh()
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
      navigational: false
      available: !root.busy
      onClicked: root.disconnect(root.activeSsid)
    }

    PanelSeparator {}

    // ---- what is nearby ----
    PanelSectionHeader {
      width: card.contentWidth
      label: "Networks"
    }

    ListView {
      id: list
      width: card.contentWidth
      // Tall enough to hold a row when there is one, capped so a crowded street
      // cannot push the rest of the panel off the screen — and never zero, or the
      // reason there is nothing to list has nowhere to be said.
      height: Math.max(
        count > 0 ? Math.min(contentHeight, root.maxListHeight) : 0,
        root.emptyMessage !== "" ? root.emptyListHeight : 0)
      clip: true
      model: root.networks
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar {}

      delegate: ChoiceRow {
        id: rowItem
        required property var modelData

        readonly property bool inFlight: root.actionSsid === rowItem.modelData.ssid && root.busy

        width: list.width
        height: Style.space(26)
        available: root.radioEnabled && !root.busy

        // Only for networks that need a key. An open network gets no glyph rather
        // than an open padlock: the absence says "open" more quietly than a
        // symbol repeated on every row would.
        glyph: root.secured(rowItem.modelData) ? Util.lock : ""
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
              anchors.verticalCenter: parent.verticalCenter
              color: index < root.signalLevel(rowItem.modelData.signal)
                ? (rowItem.modelData.inUse ? Theme.primary : Theme.muted)
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

    PanelActionButton {
      width: card.contentWidth
      label: root.scanning ? "Scanning…" : "Scan for networks"
      navigational: false
      available: root.radioEnabled && !root.failed
      onClicked: root.rescan()
    }

    // The QR, behind a toggle. It carries the network's password in the clear, so
    // it is drawn only while this is on, and generated only then — the image is
    // not sitting in the state directory waiting for a panel to be open.
    PanelSeparator {
      visible: root.qrVisible
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

    Item {
      width: card.contentWidth
      height: root.qrVisible && root.qrReady ? qrImage.implicitHeight : 0
      visible: height > 0

      SizedImage {
        id: qrImage
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(180)
        height: width
        source: root.qrPath
        fillMode: Image.PreserveAspectFit
      }
    }

    Text {
      width: card.contentWidth
      height: implicitHeight
      visible: root.qrVisible && !root.qrReady
      text: "Could not read the network password"
      color: Theme.danger
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }
}