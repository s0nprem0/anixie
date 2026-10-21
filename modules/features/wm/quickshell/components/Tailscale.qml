import QtQuick
import Quickshell.Io
import ".."
import "../Ui"

// Tailscale: whether the tailnet is up, and who else is on it.
//
// The CLI is the source of truth. There is no Quickshell service for Tailscale,
// and the JSON status already carries the backend state, this machine's names
// and every peer, so the widget does not need to parse log lines or keep its own
// idea of what connected means.
//
// It stays off the bar when the CLI is not installed, which is also how the
// widget hides on a machine that has never opted into Tailscale.
BarWidget {
  id: root

  Component.onCompleted: {
    PanelRegistry.register("tailscale", readout, panel)
    which.running = true
  }

  // A tailnet's state changes when a machine connects or a key expires, not
  // between heartbeats. Half a minute is still quick enough to watch a peer come
  // up, and halves the status process compared with fifteen seconds.
  readonly property int intervalMs: Math.max(5000, Number(root.setting("interval", 30)) * 1000)

  property bool installed: false
  property string backend: "Unknown"
  property bool running: false
  property bool needsLogin: false
  property string selfHost: ""
  property string selfDns: ""
  property string selfIp: ""
  property var peers: []
  property string lastError: ""

  readonly property string stateLabel: root.needsLogin
    ? "Needs login"
    : (root.running ? "Connected" : (root.backend === "Unknown" ? "Checking…" : root.backend))

  function firstIp(ips) {
    const list = ips || []
    for (let i = 0; i < list.length; i++) {
      if (String(list[i]).indexOf(":") === -1) return String(list[i])
    }
    return list.length > 0 ? String(list[0]) : ""
  }

  function cleanDns(name) {
    return String(name || "").replace(/\.$/, "")
  }

  function peerName(peer) {
    return String(peer.host || peer.dns || peer.ip || "Unknown machine")
  }

  function peerDetail(peer) {
    const state = peer.online ? "online" : "offline"
    return (peer.ip !== "" ? peer.ip + " · " : "") + state + (peer.os !== "" ? " · " + peer.os : "")
  }

  function copy(value) {
    const text = String(value || "")
    if (text !== "") Commands.runQuoted("wl-copy", [text])
  }

  function refresh() {
    if (!root.installed || status.running) return

    status.running = false
    status.running = true
  }

  function apply(raw) {
    try {
      const data = JSON.parse(String(raw || "{}"))
      root.backend = String(data.BackendState || "Unknown")
      root.running = root.backend === "Running"
      root.needsLogin = root.backend === "NeedsLogin" || root.backend === "NeedsMachineAuth"
      root.lastError = ""

      const self = data.Self || {}
      root.selfHost = String(self.HostName || "")
      root.selfDns = root.cleanDns(self.DNSName)
      root.selfIp = root.firstIp(self.TailscaleIPs)

      const list = []
      const peerMap = data.Peer || {}
      for (const key in peerMap) {
        const peer = peerMap[key]
        if (!peer) continue

        list.push({
          host: String(peer.HostName || ""),
          dns: root.cleanDns(peer.DNSName),
          ip: root.firstIp(peer.TailscaleIPs),
          online: peer.Online === true || peer.Active === true,
          os: String(peer.OS || ""),
          exitNode: peer.ExitNode === true,
        })
      }

      list.sort(function (a, b) {
        if (a.online !== b.online) return a.online ? -1 : 1
        return root.peerName(a).localeCompare(root.peerName(b))
      })
      root.peers = list
    } catch (e) {
      root.backend = "Unavailable"
      root.running = false
      root.needsLogin = false
      root.peers = []
      root.lastError = String(e)
    }
  }

  wantsSlot: root.installed
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: which
    running: false
    command: ["sh", "-c", "command -v tailscale"]

    stdout: StdioCollector {
      onStreamFinished: {
        root.installed = String(this.text).trim() !== ""
        if (root.installed) root.refresh()
      }
    }
  }

  Process {
    id: status
    running: false
    command: ["tailscale", "status", "--json"]

    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }
    stderr: StdioCollector {
      onStreamFinished: root.lastError = String(this.text).trim()
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.installed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: readout
    anchors.centerIn: parent
    text: ""
    hasVisualContent: true
    fixedWidth: Style.bar.iconSlot
    fixedHeight: Style.bar.iconSlot
    foreground: root.needsLogin ? Theme.danger : (root.running ? Theme.accent : Theme.muted)
    dimmed: !root.running && !root.needsLogin
    tooltipText: (root.needsLogin
      ? "Tailscale needs login · click for status"
      : (root.running
        ? "Tailscale · " + (root.selfHost !== "" ? root.selfHost : "connected")
        : "Tailscale " + root.stateLabel + " · click for status"))
      + " · right-click to refresh"

    // The mark is the official 3×3 dot grid, drawn natively so it stays crisp in
    // a bar-sized slot instead of going through an SVG at 12 pixels.
    Item {
      id: mark

      anchors.centerIn: parent
      width: Style.bar.iconSize
      height: Style.bar.iconSize

      readonly property real dot: Math.max(2, width * 0.22)
      readonly property real space: (width - dot * 3) / 2

      Grid {
        columns: 3
        rows: 3
        columnSpacing: mark.space
        rowSpacing: mark.space

        Repeater {
          model: [0.24, 0.24, 0.24, 1, 1, 1, 0.24, 1, 0.24]

          delegate: Rectangle {
            required property var modelData

            width: mark.dot
            height: mark.dot
            radius: width / 2
            color: readout.foreground
            opacity: Number(modelData)
          }
        }
      }
    }

    onPressed: function (button) {
      if (button === Qt.RightButton) root.refresh()
      else if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("tailscale")
    }
  }

  Component {
    id: panel

    Panel {
      id: card
      title: ""

      PanelHero {
        width: card.contentWidth
        title: "Tailscale"
        subtitle: root.running
          ? (root.selfHost !== "" ? root.selfHost : root.selfDns)
          : root.stateLabel + (root.lastError !== "" ? " · " + root.lastError : "")
      }

      PanelSeparator {}

      ChoiceRow {
        width: card.contentWidth
        label: "This machine"
        detail: root.selfIp !== ""
          ? root.selfIp + (root.selfDns !== "" ? " · " + root.selfDns : "")
          : "No address"
        selected: root.running
        available: root.selfIp !== ""
        onClicked: root.copy(root.selfIp)
      }

      PanelRow {
        width: card.contentWidth
        label: "Backend"
        value: root.backend
      }

      PanelSeparator {
        visible: root.peers.length > 0
      }

      PanelSectionHeader {
        width: card.contentWidth
        visible: root.peers.length > 0
        label: "Machines · click to copy the IP"
      }

      Text {
        width: card.contentWidth
        height: implicitHeight
        visible: root.running && root.peers.length === 0
        text: "No other machines on this tailnet"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Text {
        width: card.contentWidth
        height: implicitHeight
        visible: root.needsLogin
        text: "Run `tailscale up` and sign in; the widget will pick it up on the next refresh."
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.peers

        delegate: ChoiceRow {
          id: peerRow
          required property var modelData

          width: card.contentWidth
          label: root.peerName(peerRow.modelData)
          detail: root.peerDetail(peerRow.modelData)
          selected: peerRow.modelData.online
          onClicked: root.copy(peerRow.modelData.ip)
        }
      }
    }
  }
}
