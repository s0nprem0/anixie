import QtQuick
import Quickshell
import Quickshell.Services.UPower

// The low-battery warning.
//
// The bar's readout turns red at the low threshold and the power panel carries
// the numbers, but a glance is not always there: on bare Hyprland there is no
// desktop layer to put a warning on screen, and UPower's own policy actions are
// silent. So this watches the same UPower device the readout does and asks for a
// notification through the shell's own daemon, the way `reminder` does. It is
// also the only notifier now — the powerprofile watcher just acts — so the
// thresholds below are the same ones the bar and the automation use.
//
// Event-driven rather than polled. UPower reports the percentage and charge state
// over D-Bus, so a level crossing is already a signal and a timer would only be
// asking again for an answer that arrives on its own.
QtObject {
  id: root

  // The same two levels as anixie.power.batteryAutomation, rendered in so the
  // bar, the warning and the dimming cannot drift apart.
  readonly property int warnAt: @LOW_THRESHOLD@
  readonly property int criticalAt: @CRITICAL_THRESHOLD@

  readonly property var device: UPower.displayDevice
  readonly property bool present: root.device !== null && root.device.ready && root.device.isPresent

  // Derived from the charge state rather than UPower's daemon-wide `onBattery`,
  // which stays false on this machine even with a battery fitted (see the power
  // panel for the same workaround).
  readonly property bool charging: root.present && (
    root.device.state === UPowerDeviceState.Charging
    || root.device.state === UPowerDeviceState.FullyCharged
    || root.device.state === UPowerDeviceState.PendingCharge)

  readonly property int level: root.present ? Math.round(root.device.percentage * 100) : -1

  // The highest warning already given for this discharge. A level that flickers
  // across a line would otherwise notify on every event; this is reset once the
  // charger goes in or the level climbs back above the first threshold.
  property int warned: 0

  function notify(urgency, summary, body, icon) {
    Quickshell.execDetached([
      "@NOTIFY_SEND@", "-a", "Battery", "-u", urgency, "-i", icon,
      summary, body,
      "--exec", "@QUICKSHELL@", "ipc", "call", "panel", "toggle", "power"
    ])
  }

  function check() {
    // Silence on mains, and above the first line: the warning is about a
    // discharge, and there is nothing to say while there is still charge.
    if (!root.present || root.charging) {
      root.warned = 0
      return
    }

    if (root.level <= root.criticalAt && root.warned < 2) {
      root.warned = 2
      OsdHost.show("battery", "Battery critical: " + root.level + "%", "", "", "", 3000)
      root.notify("critical", "Battery critical",
        "Battery is at " + root.level + "%. Plug in now.", "battery-empty")
    } else if (root.level <= root.warnAt && root.warned < 1) {
      root.warned = 1
      OsdHost.show("battery", "Battery low: " + root.level + "%", "", "", "", 3000)
      root.notify("normal", "Battery low",
        "Battery is at " + root.level + "%. Find a charger.", "battery-caution")
    } else if (root.level > root.warnAt) {
      root.warned = 0
    }
  }

  onLevelChanged: root.check()
  onChargingChanged: root.check()

  // One check shortly after the shell starts, for a session that comes up already
  // below a line with nothing left to change afterwards. Delayed, and not run on
  // completion: UPower can answer with the state from before the shell started,
  // and that stale reading is what makes a warning fire on a machine that is
  // already plugged in — the race omarchy hit in its own Quickshell rewrite.
  property Timer settle: Timer {
    interval: 5000
    running: true
    repeat: false
    onTriggered: root.check()
  }
}
