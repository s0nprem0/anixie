import QtQuick
import ".."
import "../Ui"
import "../panels"
import Quickshell
import Quickshell.Io

// Battery readout. Both values come from FileView, which watches the sysfs
// nodes rather than re-reading them on a timer, so the percentage tracks the
// hardware instead of polling for it.
BarWidget {
  id: root

  readonly property string capacityPath: "/sys/class/power_supply/BAT0/capacity"
  readonly property string statusPath: "/sys/class/power_supply/BAT0/status"

  readonly property int level: {
    const raw = capView.text()
    const v = parseInt(String(raw).trim(), 10)
    return isNaN(v) ? -1 : v
  }
  readonly property bool charging: String(statusView.text()).trim() === "Charging"

  readonly property bool present: level >= 0
  property bool showPercent: true

  // Hidden on a machine with no battery, rather than a permanently blank slot.
  visible: present

  readonly property string glyph: {
    if (level <= 10) return Util.batteryEmpty
    if (level <= 30) return Util.batteryQuarter
    if (level <= 55) return Util.batteryHalf
    if (level <= 80) return Util.batteryThreeQuarters
    return Util.batteryFull
  }

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  FileView {
    id: capView
    path: root.capacityPath
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

  FileView {
    id: statusView
    path: root.statusPath
    printErrors: false
    watchChanges: true
    blockLoading: true
  }

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