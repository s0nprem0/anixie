import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Bluetooth

// Bluetooth status and device list. Left opens the list, right toggles the radio,
// the pair the reference bar binds to its bluetooth icon.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: root.registerPanel("bluetooth", readout, popup)

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool available: root.adapter !== null
  readonly property bool powered: root.adapter ? root.adapter.enabled : false

  // The adapter reports paired devices as well as connected ones, so the icon
  // lights only on the latter.
  readonly property var devices: root.adapter ? root.adapter.devices.values : []
  readonly property var connected: {
    const list = []
    for (let i = 0; i < root.devices.length; i++) {
      if (root.devices[i].connected) list.push(root.devices[i])
    }
    return list
  }
  readonly property int connectedCount: root.connected.length

  // Discovery runs only while the panel is open: it is what turns an empty
  // device list into something you can pair from, and leaving it on after the
  // panel closes would keep the radio scanning for nobody.
  readonly property bool discovering: root.adapter ? root.adapter.discovering : false

  wantsSlot: root.available
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function togglePower() {
    if (root.adapter) root.adapter.enabled = !root.adapter.enabled
  }

  function syncDiscovery(on) {
    if (!root.adapter) return
    root.adapter.discovering = !!(on && root.powered)
  }

  function toggleDiscovery() {
    if (!root.powered) return
    root.syncDiscovery(!root.discovering)
  }

  // Pairing is the action for a device the adapter has found but does not know
  // yet. A paired one connects, a connected one disconnects, and a device that
  // is mid-pair cancels on the second click.
  function activate(device) {
    if (!device || !root.powered) return
    if (device.pairing) device.cancelPair()
    else if (device.connected) device.disconnect()
    else if (device.paired || device.bonded) device.connect()
    else device.pair()
  }

  function label(device) {
    const name = String(device.name || device.deviceName || "").trim()
    return name !== "" ? name : String(device.address || "")
  }

  function detail(device) {
    if (device.pairing) return "pairing…"
    const state = device.connected ? "connected" : (device.paired ? "paired" : "not paired")
    // Quickshell reports the battery as a fraction, like UPower does; scale it
    // before the readout so a healthy device does not show "0.85%".
    const battery = device.batteryAvailable && device.battery > 0
      ? " · " + Math.round(device.battery * 100) + "%"
      : ""
    return state + battery
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
      if (button === Qt.LeftButton) PanelRegistry.toggle("bluetooth", readout)
      else if (button === Qt.RightButton) root.togglePower()
    }
  }

  Component {
    id: popup

    Panel {
      id: card

      // Discovery starts with the panel and stops with it. Powering the radio
      // on while the panel is open has to start it too, so the state follows
      // both events rather than only the first.
      Component.onCompleted: root.syncDiscovery(root.powered)
      Component.onDestruction: root.syncDiscovery(false)

      Connections {
        target: root
        function onPoweredChanged() { root.syncDiscovery(root.powered) }
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
        model: root.devices

        delegate: ChoiceRow {
          id: deviceRow
          required property var modelData

          readonly property var device: modelData
          readonly property bool connected: deviceRow.device.connected

          width: card.contentWidth
          label: root.label(deviceRow.device)
          detail: root.detail(deviceRow.device)
          // Connected is a state, not a selection: the row is what you click to
          // change it, so it is filled the way a chosen one is. An unpaired
          // device found by the scan is the row that starts pairing.
          selected: deviceRow.connected
          available: root.powered
          onClicked: root.activate(deviceRow.device)
        }
      }
    }
  }
}
