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

  readonly property var device: UPower.displayDevice
  readonly property bool present: root.device !== null && root.device.ready && root.device.isPresent

  // Quickshell hands over UPower's `percentage` as a fraction — 0.4 for 40% — so
  // it has to be scaled. Reading it as if it were already a percentage is what
  // made a healthy battery show 0%: Math.round(0.4) is 0.
  readonly property int level: root.present ? Math.round(root.device.percentage * 100) : -1

  readonly property bool charging: root.present
    && root.device.state === UPowerDeviceState.Charging

  property bool showPercent: true

  // Hidden on a machine with no battery, rather than a permanently blank slot.
  visible: root.present

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
    id: powerPanel
    Power {}
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: root.charging ? Util.charging : root.glyph
    labelText: !root.vertical && root.showPercent ? root.level + "%" : ""
    active: root.charging
    foreground: root.level >= 0 && root.level <= 15 && !root.charging ? Theme.danger : Theme.fg
    tooltipText: "Battery · click for power panel"

    // The percentage is a toggle rather than permanent chrome: it costs a slot
    // on a 26px bar, and the panel carries the number when it is wanted.
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        PanelHost.toggle(readout, powerPanel)
      } else if (button === Qt.RightButton) {
        root.showPercent = !root.showPercent
      }
    }
  }
}
