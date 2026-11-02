import QtQuick
import Quickshell.Io

// DNS for the active connection.
//
// Per connection, not global: nmcli keeps it on the connection profile, which
// is why it follows the network rather than the machine. An empty list means
// "whatever the router hands out", and that is a choice worth offering by name
// — the alternative is a panel that can only ever add a resolver, never go
// back to the one DHCP gave you.
QtObject {
  id: dnsState

  // The first line of a failed action, for the panel to show.
  signal failed(string message)
  // An action finished, so the panel's other facts may have changed too.
  signal changed()

  // Set by the panel: whether there is a connection, and its profile name.
  property bool connected: false
  property string connection: ""

  readonly property var providers: [
    { label: "Automatic", value: "", value6: "" },
    { label: "Cloudflare", value: "1.1.1.1 1.0.0.1", value6: "2606:4700:4700::1111 2606:4700:4700::1001" },
    { label: "Quad9", value: "9.9.9.9 149.112.112.112", value6: "2620:fe::fe 2620:fe::9" },
    { label: "Google", value: "8.8.8.8 8.8.4.4", value6: "2001:4860:4860::8888 2001:4860:4860::8844" }
  ]

  property string dns: ""
  property string dns6: ""
  property bool busy: false

  // Request generation, and the profile it was read for. A result is applied
  // only when both still match.
  property int generation: 0
  property string readConnection: ""

  // Addresses as a set, so "1.1.1.1 1.0.0.1" and "1.0.0.1,1.1.1.1" are the same
  // answer rather than two different ones.
  function key(value) {
    return String(value || "")
      .split(/[,\s]+/)
      .filter(function (part) { return part !== "" })
      .sort()
      .join(" ")
  }

  function index() {
    const current = dnsState.key(dnsState.dns)
    const current6 = dnsState.key(dnsState.dns6)
    for (let i = 0; i < dnsState.providers.length; i++) {
      const provider = dnsState.providers[i]
      if (dnsState.key(provider.value) === current && dnsState.key(provider.value6) === current6) {
        return i
      }
    }
    return -1
  }

  function refresh() {
    if (!dnsState.connected || dnsState.connection === "") {
      dnsState.dns = ""
      dnsState.dns6 = ""
      return
    }

    dnsState.generation += 1
    dnsState.readConnection = dnsState.connection
    dnsGet.expectedGeneration = dnsState.generation
    dnsGet.expectedConnection = dnsState.readConnection
    dnsGet.running = false
    dnsGet.running = true
  }

  function set(provider) {
    if (!provider || dnsState.connection === "") return
    if (dnsState.busy) return

    dnsState.busy = true
    dnsSet.command = ["wifi", "dns", "set", provider.value || "", provider.value6 || ""]
    dnsSet.running = false
    dnsSet.running = true
  }

  property Process dnsGet: Process {
    id: dnsGet
    running: false
    property int expectedGeneration: 0
    property string expectedConnection: ""
    command: ["wifi", "dns"]
    stdout: StdioCollector {}
    onExited: function (exitCode) {
      if (dnsState.generation !== dnsGet.expectedGeneration) return
      if (dnsState.connection !== dnsGet.expectedConnection) return
      if (exitCode !== 0) return

      let v4 = ""
      let v6 = ""
      const lines = String(dnsGet.stdout.text || "").split("\n")

      for (let i = 0; i < lines.length; i++) {
        if (lines[i] === "") continue
        const fields = lines[i].split("\t")
        if (fields[0] === "ipv4") v4 = fields[1] || ""
        else if (fields[0] === "ipv6") v6 = fields[1] || ""
      }

      dnsState.dns = v4
      dnsState.dns6 = v6
    }
  }

  property Process dnsSet: Process {
    id: dnsSet
    running: false
    stderr: StdioCollector { id: dnsErr }
    onExited: function (exitCode) {
      dnsState.busy = false
      if (exitCode !== 0) {
        const message = String(dnsErr.text || "").trim().split("\n")[0]
        dnsState.failed(message !== "" ? message : "Could not change DNS")
      }
      dnsState.refresh()
      dnsState.changed()
    }
  }
}
