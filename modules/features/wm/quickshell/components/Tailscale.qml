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
    root.registerPanel("tailscale", readout, panel)
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
  property var exitNodes: []
  property bool exitNodeActive: false
  property var accounts: []
  property var taildropTargets: []
  property bool busy: false
  property bool detailsPending: false
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

  // Accounts and Taildrop targets only feed the panel, so they are read when it
  // opens (and after an action that can change them) rather than on every
  // status poll. The status process itself still runs on the bar's interval.
  function refreshDetails() {
    if (!root.installed) return
    if (!accounts.running) accounts.running = true
    if (!targets.running) targets.running = true
  }

  function refreshSoon(details) {
    root.busy = true
    if (details) root.detailsPending = true
    root.refreshTimer.restart()
  }

  function connect() {
    Commands.runQuoted("tailscale", [root.running ? "down" : "up"])
    root.refreshSoon(true)
  }

  function switchAccount(id) {
    if (String(id) === "") return
    Commands.runQuoted("tailscale", ["switch", String(id)])
    root.refreshSoon(true)
  }

  function setExitNode(ip) {
    Commands.runQuoted("tailscale", ["set", "--exit-node=" + String(ip || "")])
    root.refreshSoon()
  }

  // Taildrop has no picker of its own here, so the clipboard is the source. The
  // temporary file is removed whether the command succeeds or not.
  function sendClipboard(target) {
    const destination = String(target || "") + ":"
    if (destination === ":") return

    // `--type image` is not a wildcard; ask the clipboard which concrete image
    // type it is offering, then paste that exact type.
    const command = 'type=$(wl-paste --list-types | grep -m1 "^image/") || exit 1;'
      + ' tmp=$(mktemp --suffix=.png) || exit 1;'
      + ' wl-paste --type "$type" >"$tmp"'
      + ' && tailscale file cp --name clipboard.png "$tmp" ' + Util.shellQuote(destination)
      + '; rc=$?; rm -f "$tmp"; exit $rc'
    Commands.run(command)
    root.refreshSoon()
  }

  function apply(raw) {
    try {
      const data = JSON.parse(String(raw || "{}"))
      const wasRunning = root.running
      root.backend = String(data.BackendState || "Unknown")
      root.running = root.backend === "Running"
      root.needsLogin = root.backend === "NeedsLogin" || root.backend === "NeedsMachineAuth"
      root.lastError = ""
      if (!wasRunning && root.running) root.refreshDetails()

      const self = data.Self || {}
      root.selfHost = String(self.HostName || "")
      root.selfDns = root.cleanDns(self.DNSName)
      root.selfIp = root.firstIp(self.TailscaleIPs)
      root.exitNodeActive = !!(data.ExitNodeStatus && data.ExitNodeStatus.ID)

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
          exitNodeOption: peer.ExitNodeOption === true,
        })
      }

      list.sort(function (a, b) {
        if (a.online !== b.online) return a.online ? -1 : 1
        return root.peerName(a).localeCompare(root.peerName(b))
      })
      root.peers = list
      root.exitNodes = list.filter(function (peer) { return peer.exitNodeOption })
    } catch (e) {
      root.backend = "Unavailable"
      root.running = false
      root.needsLogin = false
      root.peers = []
      root.exitNodes = []
      root.exitNodeActive = false
      root.accounts = []
      root.taildropTargets = []
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

  // `switch --list --json` is the only machine-readable account listing. Its
  // shape has changed between Tailscale releases, so the parser accepts both an
  // array and an object with an accounts key, and several spellings of the id.
  Process {
    id: accounts
    running: false
    command: ["tailscale", "switch", "--list", "--json"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(this.text || "[]"))
          const list = Array.isArray(parsed)
            ? parsed
            : (parsed.Accounts || parsed.accounts || [])
          const out = []
          for (const account of list) {
            if (!account) continue
            const id = String(account.ID || account.id || account.ProfileID || account.profileID || "")
            if (id === "") continue
            out.push({
              id: id,
              name: String(account.Nickname || account.DisplayName || account.Account || account.LoginName || account.Tailnet || id),
              detail: String(account.Tailnet || account.Account || ""),
              active: account.Active === true || account.Current === true,
            })
          }
          root.accounts = out
        } catch (e) {
          root.accounts = []
        }
      }
    }
  }

  // Taildrop targets are plain lines, not JSON. Keep the whole line as the
  // label but use its first word as the destination: older releases append the
  // address in parentheses.
  Process {
    id: targets
    running: false
    command: ["tailscale", "file", "cp", "--targets"]

    stdout: StdioCollector {
      onStreamFinished: {
        const out = []
        for (const raw of String(this.text || "").split("\n")) {
          const line = raw.trim()
          if (line === "" || /^no .*targets?/i.test(line) || /not connected/i.test(line)) continue
          const target = line.split(/\s+/)[0]
          if (target !== "") out.push({ target: target, label: line })
        }
        root.taildropTargets = out
      }
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.installed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 1800
    repeat: false
    onTriggered: {
      root.busy = false
      root.refresh()
      if (root.detailsPending) {
        root.detailsPending = false
        root.refreshDetails()
      }
    }
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
      else if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("tailscale", readout)
    }
  }

  Component {
    id: panel

    Panel {
      id: card
      title: ""

      Component.onCompleted: {
        root.refreshDetails()
        root.refresh()
      }

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

      PanelActionButton {
        width: card.contentWidth
        label: root.busy
          ? "Working…"
          : (root.running ? "Disconnect" : (root.needsLogin ? "Log in" : "Connect"))
        navigational: false
        outlined: root.running
        available: !root.busy
        onClicked: root.connect()
      }

      PanelSeparator {
        visible: root.accounts.length > 0
      }

      PanelSectionHeader {
        width: card.contentWidth
        visible: root.accounts.length > 0
        label: "Accounts"
      }

      Repeater {
        model: root.accounts

        delegate: ChoiceRow {
          id: accountRow
          required property var modelData

          width: card.contentWidth
          label: accountRow.modelData.name
          detail: accountRow.modelData.detail
          selected: accountRow.modelData.active
          onClicked: root.switchAccount(accountRow.modelData.id)
        }
      }

      PanelSeparator {
        visible: root.running
      }

      PanelSectionHeader {
        width: card.contentWidth
        visible: root.running
        label: "Exit node"
      }

      ChoiceRow {
        width: card.contentWidth
        visible: root.running
        label: "None"
        detail: "Direct connection"
        selected: !root.exitNodeActive
        onClicked: root.setExitNode("")
      }

      Repeater {
        model: root.exitNodes

        delegate: ChoiceRow {
          id: exitRow
          required property var modelData

          width: card.contentWidth
          visible: root.running
          label: root.peerName(exitRow.modelData)
          detail: exitRow.modelData.ip + (exitRow.modelData.online ? " · online" : " · offline")
          selected: exitRow.modelData.exitNode
          available: exitRow.modelData.online
          onClicked: root.setExitNode(exitRow.modelData.ip)
        }
      }

      PanelSeparator {
        visible: root.running && root.taildropTargets.length > 0
      }

      PanelSectionHeader {
        width: card.contentWidth
        visible: root.running && root.taildropTargets.length > 0
        label: "Taildrop · send clipboard image"
      }

      Repeater {
        model: root.taildropTargets

        delegate: ChoiceRow {
          id: targetRow
          required property var modelData

          width: card.contentWidth
          visible: root.running
          label: targetRow.modelData.label
          detail: "Send the image on the clipboard"
          onClicked: root.sendClipboard(targetRow.modelData.target)
        }
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
        text: "Log in above and finish signing in your browser; the widget will pick it up on the next refresh."
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
