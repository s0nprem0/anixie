pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Bluetooth

// Bluetooth status and device list.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: root.registerPanel("bluetooth", readout, popup)

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool available: root.adapter !== null && root.adapter !== undefined
  readonly property bool powered: root.available && root.adapter.enabled
  property var discoveryAdapter: null

  readonly property var devices: root.adapter && root.adapter.devices ? (root.adapter.devices.values || []) : []
  readonly property var connected: {
    const list = []
    const d = root.devices || []
    for (let i = 0; i < d.length; i++) {
      if (d[i] && d[i].connected) list.push(d[i])
    }
    return list
  }
  readonly property int connectedCount: root.connected.length

  readonly property bool discovering: root.adapter && root.adapter.discovering ? true : false

  wantsSlot: root.available
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function togglePower() {
    if (!root.adapter) return
    try {
      root.adapter.enabled = !root.adapter.enabled
    } catch (e) {}
  }

  function stopDiscovery() {
    if (root.discoveryAdapter) {
      try {
        root.discoveryAdapter.discovering = false
      } catch (e) {}
      root.discoveryAdapter = null
    } else if (root.adapter) {
      try {
        root.adapter.discovering = false
      } catch (e) {}
    }
  }

  function syncDiscovery(on) {
    if (!root.available || !root.adapter) return
    const want = !!on && root.powered
    try {
      if (want) {
        if (root.discoveryAdapter && root.discoveryAdapter !== root.adapter) {
          try { root.discoveryAdapter.discovering = false } catch (e) {}
        }
        root.adapter.discovering = true
        root.discoveryAdapter = root.adapter
      } else {
        if (root.discoveryAdapter === root.adapter) {
          try { root.adapter.discovering = false } catch (e) {}
          root.discoveryAdapter = null
        } else if (!root.discoveryAdapter) {
          try { root.adapter.discovering = false } catch (e) {}
        }
      }
    } catch (e) {}
  }

  function toggleDiscovery() {
    if (!root.powered) return
    root.syncDiscovery(!root.discovering)
  }

  function activate(device) {
    if (!device || !root.powered || !root.available) return
    try {
      if (device.pairing) {
        if (typeof device.cancelPair === "function") device.cancelPair()
        return
      }
      if (device.connected) {
        if (typeof device.disconnect === "function") device.disconnect()
        return
      }
      if (device.paired || device.bonded) {
        if (typeof device.connect === "function") device.connect()
        return
      }
      if (typeof device.pair === "function") device.pair()
    } catch (e) {}
  }

  function label(device) {
    if (!device) return ""
    const name = device.name !== undefined ? String(device.name) : (device.deviceName !== undefined ? String(device.deviceName) : "")
    const trimmed = name.trim()
    if (trimmed !== "") return trimmed
    const addr = device.address !== undefined ? String(device.address) : ""
    return addr
  }

  function detail(device) {
    if (!device) return ""
    if (device.pairing) return "pairing…"
    const connected = !!device.connected
    const paired = !!(device.paired || device.bonded)
    const state = connected ? "connected" : (paired ? "paired" : "not paired")
    let battery = ""
    try {
      if (device.batteryAvailable) {
        const b = Number(device.battery)
        if (isFinite(b)) {
          if (b >= 0 && b <= 1) {
            const pct = Math.round(b * 100)
            battery = " · " + pct + "%"
          } else if (b >= 0 && b <= 100) {
            battery = " · " + Math.round(b) + "%"
          }
        }
      } else if (device.battery !== undefined && device.battery !== null) {
        const b = Number(device.battery)
        if (isFinite(b) && b === 0) {
          battery = " · 0%"
        }
      }
    } catch (e) {}
    return state + battery
  }

  function sortedDevices() {
    const d = root.devices || []
    const out = []
    for (let i = 0; i < d.length; i++) {
      if (d[i]) out.push(d[i])
    }
    out.sort(function (a, b) {
      const ac = a && a.connected ? 1 : 0
      const bc = b && b.connected ? 1 : 0
      if (ac !== bc) return bc - ac
      const ap = a && a.pairing ? 1 : 0
      const bp = b && b.pairing ? 1 : 0
      if (ap !== bp) return bp - ap
      const apd = a && (a.paired || a.bonded) ? 1 : 0
      const bpd = b && (b.paired || b.bonded) ? 1 : 0
      if (apd !== bpd) return bpd - apd
      const an = root.label(a).toLowerCase()
      const bn = root.label(b).toLowerCase()
      if (an < bn) return -1
      if (an > bn) return 1
      return 0
    })
    return out
  }

  BarIconButton {
    id: readout
    contextMenu: function () {
      return [
        { label: "Bluetooth panel", glyph: Util.bluetooth, action: function () { PanelRegistry.toggle("bluetooth", readout) } },
        {
          label: root.powered ? "Turn Bluetooth off" : "Turn Bluetooth on",
          action: function () { root.togglePower() }
        }
      ]
    }
    anchors.centerIn: parent
    text: Util.bluetooth
    labelText: root.vertical || root.connectedCount === 0 ? "" : String(root.connectedCount)
    active: root.powered && root.connectedCount > 0
    dimmed: !root.powered
    tooltipText: !root.powered
      ? "Bluetooth off · Super+Ctrl+B · right-click for menu"
      : (root.connectedCount > 0
        ? root.connectedCount + " connected · Super+Ctrl+B"
        : "Bluetooth on · Super+Ctrl+B")

    onPressed: function (button) {
    if (button === Qt.LeftButton) {
      PanelRegistry.toggle("bluetooth", readout)
      return
    }
  }
  }

  Component {
    id: popup

    Panel {
      id: card

      Component.onCompleted: root.syncDiscovery(root.powered)
      Component.onDestruction: root.stopDiscovery()

      Connections {
        target: root
        function onPoweredChanged() { root.syncDiscovery(root.powered) }
        function onAdapterChanged() { root.syncDiscovery(root.powered) }
      }

      PanelHero {
        width: card.contentWidth
        glyph: Util.bluetooth
        title: "Bluetooth"
        subtitle: root.available
          ? (root.adapter.name || "Adapter")
          : "No adapter"
        controlWidth: radioSwitch.implicitWidth

        // The radio, in the panel as well as on the bar. Turning it off from the
        // bar needs a right-click on a sixteen-pixel glyph; turning it on and off
        // is what this panel is for, so the control belongs here too.
        ToggleSwitch {
          id: radioSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.available
          checked: root.powered
          onToggled: root.togglePower()
        }
      }

      PanelSeparator {}

      PanelSectionHeader {
        width: card.contentWidth
        label: "Devices"
        action: root.discovering ? "Scanning…" : "Scan"
        actionEnabled: root.powered
        onActionTriggered: root.toggleDiscovery()
      }

      Text {
        width: card.contentWidth
        visible: !root.available
        height: implicitHeight
        text: "This machine has no Bluetooth adapter"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Text {
        width: card.contentWidth
        visible: root.available && root.devices.length === 0
        height: implicitHeight
        // Three reasons to be empty, and each says which it is: a radio that is
        // off finds nothing because nothing is looking, a scan in progress has
        // not found anything yet, and an idle scan has nothing to show.
        text: !root.powered
          ? "Bluetooth is off"
          : (root.discovering
            ? "Searching for devices…"
            : "No devices found. Put yours in pairing mode, then scan.")
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.sortedDevices()

        delegate: ChoiceRow {
          id: deviceRow
          required property var modelData

          readonly property var device: modelData
          readonly property bool connected: deviceRow.device ? !!deviceRow.device.connected : false

          width: card.contentWidth
          label: root.label(deviceRow.device)
          detail: root.detail(deviceRow.device)
          selected: deviceRow.connected
          available: root.powered
          onClicked: root.activate(deviceRow.device)
        }
      }
    }
  }
}
