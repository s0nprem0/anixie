pragma ComponentBehavior: Bound
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
  readonly property bool present: root.device !== null && !!root.device.ready && !!root.device.isPresent
  readonly property bool ready: root.present && root.device.percentage !== undefined && root.device.percentage !== null

  // Quickshell hands over UPower's `percentage` as a fraction — 0.4 for 40% — so
  // it has to be scaled. Reading it as if it were already a percentage is what
  // made a healthy battery show 0%: Math.round(0.4) is 0.
  readonly property real percentage: root.ready ? Number(root.device.percentage) : NaN
  readonly property int level: (root.ready && isFinite(root.percentage))
    ? Math.max(0, Math.min(100, Math.round(root.percentage * 100)))
    : -1

  readonly property int state: root.ready && root.device.state !== undefined ? Number(root.device.state) : -1
  readonly property bool charging: root.ready && root.state === UPowerDeviceState.Charging
  readonly property bool fullyCharged: root.ready && root.state === UPowerDeviceState.FullyCharged
  readonly property bool pendingCharge: root.ready && root.state === UPowerDeviceState.PendingCharge
  readonly property bool discharging: root.ready && root.state === UPowerDeviceState.Discharging
  readonly property bool pendingDischarge: root.ready && root.state === UPowerDeviceState.PendingDischarge
  readonly property bool empty: root.ready && root.state === UPowerDeviceState.Empty
  readonly property bool unknown: !root.ready

  readonly property int lowThreshold: @LOW_THRESHOLD@

  // Persist via existing module setting mechanism if available; fall back to default
  property bool showPercent: root.setting ? (root.setting("showPercent", true) !== false) : true
  onShowPercentChanged: {
    try {
      if (root.entry) root.entry.showPercent = root.showPercent
    } catch (e) {}
  }

  // Hidden on a machine with no battery, rather than a permanently blank slot.
  wantsSlot: root.present && root.ready

  readonly property string glyph: {
    if (root.level <= 0) return Util.batteryEmpty
    if (root.level <= 10) return Util.batteryEmpty
    if (root.level <= 30) return Util.batteryQuarter
    if (root.level <= 55) return Util.batteryHalf
    if (root.level <= 80) return Util.batteryThreeQuarters
    return Util.batteryFull
  }

  readonly property bool lowBattery: root.ready && root.level >= 0 && root.level <= root.lowThreshold
  readonly property bool criticalBattery: root.ready && root.level >= 0 && root.level <= 10

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
    text: (root.charging && !root.criticalBattery) ? Util.charging : root.glyph
    labelText: (!root.vertical && root.showPercent && root.ready && root.level >= 0) ? root.level + "%" : ""
    active: root.charging || root.fullyCharged || root.pendingCharge
    useActiveColor: root.charging || root.fullyCharged || root.pendingCharge
    foreground: (root.lowBattery && !root.charging && !root.fullyCharged && !root.pendingCharge)
      ? Theme.danger
      : (root.criticalBattery ? Theme.danger : Theme.fg)
    tooltipText: root.ready
      ? ("Battery " + root.level + "%" + (root.fullyCharged ? " · Fully charged" : (root.charging ? " · Charging" : (root.pendingCharge ? " · Plugged in" : (root.discharging ? " · Discharging" : "")))))
        + " · Super+Ctrl+P · Left-click Power · Right-click toggle %"
      : (root.present ? "Battery · Preparing…" : "Battery unavailable")

    // The percentage is a toggle rather than permanent chrome: some bars are too
    // narrow for it, and the panel carries the number when it is wanted.
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) {
        PanelRegistry.toggle("power", readout)
      }
    }
  }
}
