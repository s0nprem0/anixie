import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Bluetooth

// Bluetooth status and device list. Left opens the list, right toggles the radio,
// the pair the reference bar binds to its bluetooth icon.
BarWidget {
  id: root

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

  visible: root.available
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  function togglePower() {
    if (root.adapter) root.adapter.enabled = !root.adapter.enabled
  }

  function label(device) {
    const name = device.name !== undefined && device.name !== "" ? device.name : device.address
    const battery = device.battery !== undefined && device.battery > 0 ? "  " + device.battery + "%" : ""
    return name + battery
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.bluetooth
    labelText: root.vertical || root.connectedCount === 0 ? "" : String(root.connectedCount)
    active: root.powered && root.connectedCount > 0
    dimmed: !root.powered
    tooltipText: !root.powered
      ? "Bluetooth off · right-click to turn on"
      : (root.connectedCount > 0
        ? root.connectedCount + " connected · left-click for devices"
        : "Bluetooth on · left-click for devices")

    onPressed: function (button) {
      if (button === Qt.LeftButton) PanelHost.toggle(readout, popup)
      else if (button === Qt.RightButton) root.togglePower()
    }
  }

  Component {
    id: popup

    Panel {
      title: "Bluetooth"
      maxWidth: Style.space(320)

      Column {
        spacing: Style.space(4)
        width: Style.space(272)

        Text {
          text: root.adapter
            ? (root.adapter.name || "Adapter") + (root.powered ? " · on" : " · off")
            : "No adapter"
          color: root.powered ? Theme.muted : Theme.danger
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.devices.length === 0
          text: "No devices"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.devices

          delegate: WidgetButton {
            id: row
            required property var modelData

            readonly property var device: modelData

            fixedWidth: Style.space(272)
            fixedHeight: Style.space(26)
            text: root.label(row.device)
            fontSize: Style.font.bodySmall
            foreground: row.device.connected ? Theme.accent : Theme.fg
            active: false
            tooltipText: row.device.connected ? "Click to disconnect" : "Click to connect"

            onPressed: function () {
              if (row.device.connected) row.device.disconnect()
              else row.device.connect()
            }
          }
        }
      }
    }
  }
}
