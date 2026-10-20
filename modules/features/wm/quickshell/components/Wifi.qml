import QtQuick
import ".."
import "../Ui"
import "../panels" as Panels
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wifi readout, from NetworkManager through Quickshell.Networking.
//
// This used to run `nmcli device wifi list` every ten seconds. That command is
// not a status query: when NetworkManager's cache is stale it triggers a real
// radio scan, which took about 3.2 seconds once in five runs and drew power each
// time. The Networking service reads the same state over D-Bus, and its device
// only scans while `scannerEnabled` is set — which is off unless the wifi panel
// asks for it.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: PanelRegistry.register("network", readout, wifiPanel)

  // The wifi device that is connected, if there is one.
  readonly property var device: {
    const list = Networking.devices.values || []
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === DeviceType.Wifi && list[i].connected) return list[i]
    }
    return null
  }

  // The network that device is on.
  readonly property var active: {
    if (!root.device) return null
    const nets = root.device.networks.values || []
    for (let i = 0; i < nets.length; i++) {
      if (nets[i].connected) return nets[i]
    }
    return null
  }

  readonly property bool connected: root.active !== null
  readonly property string ssid: root.active ? String(root.active.name) : ""
  readonly property int signal: root.active ? Math.round(Number(root.active.signalStrength) * 100) : 0

  // How many of the four bars are filled. The thresholds match the network
  // panel's, so the bar and the list agree. Zero when the device is not
  // connected: an empty staircase says "no signal" more directly than a full
  // one would, and it is what the slot keeps showing while the network is down.
  readonly property int level: root.connected
    ? (root.signal >= 70 ? 4 : root.signal >= 45 ? 3 : root.signal >= 20 ? 2 : 1)
    : 0

  // The service reports state rather than failing to run, so there is no
  // separate "query failed" case left. Kept as a property because the tooltip
  // still has a branch for it.
  readonly property bool failed: false

  readonly property bool resolved: connected && ssid !== ""

  // The module stays when the network drops: losing the slot reflows the bar
  // and takes away the thing that opens the panel to fix it. The bars go empty
  // and the tooltip says not connected, but the slot is still the way in.
  wantsSlot: true

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  // Four ascending bars, filled by the strength the device reports, in place
  // of a glyph that looked the same at one bar and at full. The name and the
  // exact percentage stay in the tooltip; the bar is for the glance. A
  // `WidgetButton` rather than a `BarIconButton`, because the visual content is
  // the bars, not a font glyph.
  WidgetButton {
    id: readout
    anchors.centerIn: parent
    keepSpace: true
    fixedWidth: Style.bar.iconSlot
    fixedHeight: Style.bar.iconSlot
    text: ""
    labelVisible: false
    // No text of its own, so the base class's "has something to draw" test has
    // to be told about the bars; otherwise the button hides itself at opacity 0.
    hasVisualContent: true

    // Same four bars as the panel's rows: width 3, spacing 2, step 3, standing
    // on a shared bottom, so the filled count reads as a staircase rather than
    // as dashes at different heights.
    Row {
      anchors.centerIn: parent
      spacing: 2

      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          width: 3
          height: 4 + index * 3
          radius: Theme.cornerRadius
          anchors.bottom: parent.bottom
          color: index < root.level
            ? readout.foreground
            : Qt.rgba(readout.foreground.r, readout.foreground.g, readout.foreground.b, 0.12)
        }
      }
    }

    foreground: root.failed ? Theme.danger : Theme.fg
    tooltipText: root.failed
      ? "Wi-Fi unavailable · Super+Ctrl+W"
      : (root.resolved
        ? root.ssid + " · " + root.signal + "% · Super+Ctrl+W"
        : "Wi-Fi not connected · Super+Ctrl+W")

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("network")
      else if (button === Qt.RightButton) root.openSettings()
    }
  }

  // Declared as an id rather than built inline: `Component { ... }` is an
  // object declaration, so it cannot be passed as a call argument.
  Component {
    id: wifiPanel
    // Qualified: Quickshell.Networking has a `Network` of its own, and the later
    // import wins, which made this the service's type and failed the whole bar.
    Panels.Network {}
  }

  function openSettings() {
    openProc.command = ["nm-connection-editor"]
    openProc.running = true
  }

  Process {
    id: openProc
    running: false
  }
}
