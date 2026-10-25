import QtQuick
import ".."
import "../Ui"
import "../panels"
import Quickshell
import Quickshell.Services.UPower

// Battery readout, taken from UPower rather than from sysfs: it normalises the
// kernel's micro-units, is event-driven, and finds the machine's battery
// without being told what it is called.
BarWidget {
  id: root

  // Reachable by hotkey as well as by click.
  Component.onCompleted: {
    root.registerPanel("power", readout, powerPanel)
    root.registerPanel("session", readout, sessionPanel)
  }

  readonly property var device: UPower.displayDevice
  readonly property bool present: root.device !== null && root.device.ready && root.device.isPresent

  // Quickshell hands over UPower's `percentage` as a fraction — 0.4 for 40% — so
  // it has to be scaled. Reading it as if it were already a percentage is what
  // made a healthy battery show 0%: Math.round(0.4) is 0.
  readonly property int level: root.present ? Math.round(root.device.percentage * 100) : -1

  readonly property bool charging: root.present
    && root.device.state === UPowerDeviceState.Charging

  // On by default: the number is the part of the readout worth glancing at, and
  // the panel carries the rest. Right-click hides it again on a bar where the
  // extra slot is not wanted.
  property bool showPercent: true

  // Hidden on a machine with no battery, rather than a permanently blank slot.
  wantsSlot: root.present

  readonly property string glyph: {
    if (root.level <= 10) return Util.batteryEmpty
    if (root.level <= 30) return Util.batteryQuarter
    if (root.level <= 55) return Util.batteryHalf
    if (root.level <= 80) return Util.batteryThreeQuarters
    return Util.batteryFull
  }

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  // Declared as an id rather than built inline: `Component { ... }` is an
  // object declaration, so it cannot be passed as a call argument.
  Component {
    id: sessionPanel
    Session {}
  }

  Component {
    id: powerPanel
    Power {}
  }

  BarIconButton {
    id: readout
    contextMenu: function () {
      return [
        {
          label: root.showPercent ? "Hide percentage" : "Show percentage",
          action: function () { root.showPercent = !root.showPercent }
        },
        { separator: true },
        { label: "Power panel", glyph: Util.bolt, action: function () { PanelRegistry.toggle("power", readout) } },
        { label: "Session menu", glyph: Util.lock, action: function () { PanelRegistry.toggle("session", readout) } }
      ]
    }
    anchors.centerIn: parent
    text: root.charging ? Util.charging : root.glyph
    labelText: !root.vertical && root.showPercent ? root.level + "%" : ""
    active: root.charging
    foreground: root.level >= 0 && root.level <= @LOW_THRESHOLD@ && !root.charging ? Theme.danger : Theme.fg
    tooltipText: (root.present ? "Battery " + root.level + "%" : "Battery")
      + " · Super+Ctrl+P · right-click for menu"

    // The percentage is a toggle rather than permanent chrome: some bars are too
    // narrow for it, and the panel carries the number when it is wanted.
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        PanelRegistry.toggle("power", readout)
      } else if (button === Qt.RightButton) {
        root.showPercent = !root.showPercent
      }
    }
  }
}
