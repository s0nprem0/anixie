import QtQuick
import Quickshell.Io

// The Wi-Fi band. NetworkManager keeps the preference on the connection
// profile. The current band comes from the access point, while the selection is
// what the profile will ask for on the next association.
QtObject {
  id: bandState

  // The first line of a failed action, for the panel to show.
  signal failed(string message)
  // An action finished, so the panel's other facts may have changed too.
  signal changed()

  // Set by the panel: whether there is a connection, the device and the SSID.
  property bool connected: false
  property string device: ""
  property string ssid: ""

  property string band: ""
  property var available: []
  property string selection: "auto"
  property bool busy: false

  // Request generation, and the device and SSID it was read for. A result is
  // applied only when all three still match.
  property int generation: 0
  property string readDevice: ""
  property string readSsid: ""

  readonly property var options: {
    const labels = { "2.4": "2.4 GHz", "5": "5 GHz", "6": "6 GHz" }
    const options = [{ label: "Automatic", value: "auto" }]
    let listed = false

    for (let i = 0; i < bandState.available.length; i++) {
      const value = bandState.available[i]
      if (labels[value]) options.push({ label: labels[value], value: value })
      if (value === bandState.selection) listed = true
    }

    if (bandState.selection !== "auto" && !listed) {
      options.push({
        label: (labels[bandState.selection] || bandState.selection) + " (unavailable)",
        value: bandState.selection
      })
    }

    return options
  }

  function index() {
    for (let i = 0; i < bandState.options.length; i++) {
      if (bandState.options[i].value === bandState.selection) return i
    }
    return 0
  }

  // A network row's band: the one in use for the connected network, otherwise
  // every band the access point was seen on.
  function label(item) {
    if (!item) return ""

    const bands = item.inUse && bandState.band !== ""
      ? [bandState.band]
      : (item.bands || [])

    return bands.length > 0 ? bands.join("/") + " GHz" : ""
  }

  // Deferred to the end of the event-loop turn: the panel calls this from its
  // own change handlers, and the inputs bound from it may not have caught up
  // yet. A read tagged with the previous SSID would be discarded on arrival.
  // Several refreshes in one turn also become one read.
  property bool refreshQueued: false

  function refresh() {
    if (bandState.refreshQueued) return
    bandState.refreshQueued = true
    Qt.callLater(bandState.read)
  }

  function read() {
    bandState.refreshQueued = false
    if (!bandState.connected) {
      bandState.band = ""
      bandState.available = []
      bandState.selection = "auto"
      return
    }

    bandState.generation += 1
    bandState.readDevice = bandState.device
    bandState.readSsid = bandState.ssid
    bandGet.expectedGeneration = bandState.generation
    bandGet.expectedDevice = bandState.readDevice
    bandGet.expectedSsid = bandState.readSsid
    bandGet.running = false
    bandGet.running = true
  }

  function set(value) {
    const allowed = bandState.options.some(function (option) { return option.value === value })
    if (!allowed || value === bandState.selection) return

    bandState.busy = true
    bandSet.command = ["wifi", "band", value]
    bandSet.running = false
    bandSet.running = true
  }

  property Process bandGet: Process {
    id: bandGet
    running: false
    property int expectedGeneration: 0
    property string expectedDevice: ""
    property string expectedSsid: ""
    command: ["wifi", "band"]
    stdout: StdioCollector {}
    onExited: function (exitCode) {
      if (bandState.generation !== bandGet.expectedGeneration) return
      if (bandState.device !== bandGet.expectedDevice) return
      if (bandState.ssid !== bandGet.expectedSsid) return
      if (exitCode !== 0) return

      let band = ""
      let available = []
      let selected = "auto"
      const lines = String(bandGet.stdout.text || "").split("\n")

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

      bandState.band = band
      bandState.available = available
      bandState.selection = selected
    }
  }

  property Process bandSet: Process {
    id: bandSet
    running: false
    stderr: StdioCollector { id: bandSetErr }
    onExited: function (exitCode) {
      bandState.busy = false

      if (exitCode !== 0) {
        const message = String(bandSetErr.text || "").trim().split("\n")[0]
        bandState.failed(message !== "" ? message : "Could not change the Wi-Fi band")
      }

      bandState.refresh()
      bandState.changed()
    }
  }
}
