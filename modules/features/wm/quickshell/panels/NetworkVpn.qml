pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../Ui"
import "Nmcli.js" as Nmcli

// NetworkManager's own VPN, WireGuard and tun connections. Tailscale shows up
// here as its tun link; the widget on the bar still owns the tailnet itself,
// and this is the same connection seen from the network layer.
//
// One read for the list, then one action at a time.
QtObject {
  id: vpnState

  // The first line of a failed action, for the panel to show.
  signal failed(string message)
  // An action finished, so the panel's other facts may have changed too.
  signal changed()

  property var list: []
  property bool busy: false
  property string pendingName: ""
  property bool pendingUp: false

  // Request generation for the list read. A result is applied only when its
  // generation still matches.
  property int generation: 0

  function refresh() {
    vpnState.generation += 1
    vpnList.expectedGeneration = vpnState.generation
    vpnList.running = false
    vpnList.running = true
  }

  function toggle(vpn) {
    if (!vpn || vpnState.busy) return

    vpnState.busy = true
    vpnState.pendingName = String(vpn.name || "")
    vpnState.pendingUp = !vpn.active
    vpnAction.command = ["nmcli", "connection", vpn.active ? "down" : "up", vpn.name]
    vpnAction.running = false
    vpnAction.running = true
  }

  // `-t` escapes separators in a profile name, so the type and the active flag
  // are taken from the two ends of the line rather than by splitting the name on
  // a colon it may contain.
  property Process vpnList: Process {
    id: vpnList
    running: false
    property int expectedGeneration: 0
    command: ["sh", "-c", "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null || true"]
    stdout: StdioCollector {}
    onExited: function (exitCode) {
      if (vpnState.generation !== vpnList.expectedGeneration) return
      if (exitCode !== 0) return

      const out = []
      const lines = String(vpnList.stdout.text || "").split("\n")

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i]
        if (line === "") continue

        const activeAt = line.lastIndexOf(":")
        if (activeAt < 0) continue
        const typeAt = line.lastIndexOf(":", activeAt - 1)
        if (typeAt < 0) continue

        const name = Nmcli.decode(line.slice(0, typeAt))
        const type = line.slice(typeAt + 1, activeAt)
        if (name === "" || name === "lo") continue
        // Keep VPN and WireGuard links. A tun device is only a VPN candidate when
        // NetworkManager reports it as one of the VPN-like types above.
        if (type !== "vpn" && type !== "wireguard" && type !== "tun") continue

        out.push({ name: name, type: type, active: line.slice(activeAt + 1) === "yes" })
      }

      vpnState.list = out
    }
  }

  property Process vpnAction: Process {
    id: vpnAction
    running: false
    stderr: StdioCollector { id: vpnError }
    onExited: function (exitCode) {
      vpnState.busy = false

      if (exitCode !== 0) {
        const message = String(vpnError.text || "").trim().split("\n")[0]
        vpnState.failed(message !== "" ? message : "Could not change the VPN")
      }

      if (exitCode === 0 && vpnState.pendingName !== "") {
        OsdHost.show("vpn", vpnState.pendingUp ? "VPN connected: " + vpnState.pendingName : "VPN disconnected: " + vpnState.pendingName, "", "", "", 1500)
      }
      vpnState.pendingName = ""

      vpnState.refresh()
      vpnState.changed()
    }
  }
}
