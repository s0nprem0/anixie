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
  Component.onCompleted: PanelRegistry.register("bluetooth", readout, popup)

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

  wantsSlot: root.available
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function togglePower() {
    if (root.adapter) root.adapter.enabled = !root.adapter.enabled
  }

function label(device) {
  return device.name !== undefined && device.name !== "" ? device.name : device.address
}

function detail(device) {
  const state = device.connected ? "connected" : "paired"
  const battery = device.battery !== undefined && device.battery > 0 ? " · " + device.battery + "%" : ""
  return state + battery
}

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.bluetooth
    labelText: root.vertical || root.connectedCount === 0 ? "" : String(root.connectedCount)
    active: root.powered && root.connectedCount > 0
    dimmed: !root.powered
    tooltipText: !root.powered
      ? "Bluetooth off · Super+Ctrl+B · right-click to turn on"
      : (root.connectedCount > 0
        ? root.connectedCount + " connected · Super+Ctrl+B"
        : "Bluetooth on · Super+Ctrl+B")

    onPressed: function (button) {
      if (button === Qt.LeftButton) PanelRegistry.toggle("bluetooth")
      else if (button === Qt.RightButton) root.togglePower()
    }
  }

  Component {
    id: popup

    Panel {
      id: card

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
        // Two different reasons to be empty, and each says which it is: a radio
        // that is off finds nothing because nothing is looking.
        text: root.powered ? "No devices paired" : "Bluetooth is off"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
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
          // change it, so it is filled the way a chosen one is.
          selected: deviceRow.connected
          available: root.powered
          onClicked: {
            if (deviceRow.connected) deviceRow.device.disconnect()
            else deviceRow.device.connect()
          }
        }
      }
    }
  }
}
