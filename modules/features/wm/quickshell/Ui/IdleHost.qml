pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import ".."

// Idle, screensaver and the automatic lock.
//
// The shell owns the whole cycle now: a Wayland idle notification starts it, a
// screensaver covers the desktop, the display blanks, and the session locks. The
// old hypridle service is kept only as the pre-suspend guard until this path has
// been proven; its listeners are gone.
//
// Timings follow the previous hypridle config, with a visual screensaver in the
// gap before the display blanked: screensaver at 2.5 minutes, display off at 5,
// lock at 10, and suspend at 30 on battery only. `respectInhibitors` keeps the
// stay-awake service working without a second mechanism.
QtObject {
  id: root

  readonly property int screensaverSeconds: 150
  readonly property int blankSeconds: 300
  readonly property int lockSeconds: 600
  readonly property int suspendSeconds: 1800

  property bool enabled: true
  property bool screensaverShown: false
  property bool inCycle: false
  property bool displayBlanked: false

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/idle"

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
  }

  Component.onCompleted: {
    try {
      if (String(root.stateFile.text()).trim() === "off") root.enabled = false
    } catch (e) {
      // No file yet: the idle lock starts on.
    }

    root.pushIndicator()
    Qt.callLater(root.onIdleChanged)
  }

  function remember(value) {
    try {
      root.stateFile.setText(value ? "on\n" : "off\n")
    } catch (e) {
    }
  }

  function pushIndicator() {
    IndicatorHost.setIdle(root.enabled ? "on" : "off")
  }

  function applyEnabled(value) {
    root.enabled = !!value
    root.pushIndicator()
    if (!root.enabled) root.cancelCycle()
    Qt.callLater(root.onIdleChanged)
  }

  function setEnabled(value) {
    root.applyEnabled(value)
    root.remember(root.enabled)
    return root.enabled ? "on" : "off"
  }

  function toggle() {
    return root.setEnabled(!root.enabled)
  }

  function cancelCycle() {
    root.inCycle = false
    root.screensaverShown = false
    blankTimer.stop()
    lockTimer.stop()
    suspendTimer.stop()
  }

  function startCycle() {
    if (root.inCycle) return

    root.inCycle = true
    root.screensaverShown = true
    blankTimer.restart()
    lockTimer.restart()
    suspendTimer.restart()
  }

  function wake() {
    root.cancelCycle()

    if (root.displayBlanked) {
      root.displayBlanked = false
      root.dpms("on")
    }
  }

  function dpms(action) {
    Quickshell.execDetached([
      "hyprctl", "dispatch", "hl.dsp.dpms({action = \"" + String(action) + "\"})"
    ])
  }

  function onIdleChanged() {
    if (idleMonitor.isIdle && root.enabled && !LockHost.locked) root.startCycle()
    else if (!idleMonitor.isIdle) root.wake()
  }

  function lockNow() {
    root.cancelCycle()
    LockHost.lock()
  }

  function lockAndSuspend() {
    root.cancelCycle()
    LockHost.lockAndSuspend()
  }

  // ---- suspend on battery ----

  readonly property var device: UPower.displayDevice
  readonly property bool batteryPresent: root.device !== null && root.device.ready && root.device.isPresent
  readonly property bool charging: root.batteryPresent && (
    root.device.state === UPowerDeviceState.Charging
    || root.device.state === UPowerDeviceState.FullyCharged
    || root.device.state === UPowerDeviceState.PendingCharge)

  function suspendIfOnBattery() {
    if (!root.batteryPresent || root.charging) return
    root.lockAndSuspend()
  }

  // ---- the cycle ----

  property IdleMonitor idleMonitor: IdleMonitor {
    enabled: root.enabled && !LockHost.locked
    timeout: Math.max(1, root.screensaverSeconds)
    respectInhibitors: true
    onIsIdleChanged: root.onIdleChanged()
  }

  // Unlocking re-enables the monitor; if the session is already idle again, the
  // monitor's change signal may have fired while it was disabled.
  property Connections lockWatch: Connections {
    target: LockHost
    function onLockedChanged() {
      if (LockHost.locked) root.cancelCycle()
      else Qt.callLater(root.onIdleChanged)
    }
  }

  property Timer blankTimer: Timer {
    interval: Math.max(0, (root.blankSeconds - root.screensaverSeconds) * 1000)
    repeat: false
    onTriggered: {
      if (!root.inCycle) return
      root.displayBlanked = true
      root.dpms("off")
    }
  }

  property Timer lockTimer: Timer {
    interval: Math.max(0, (root.lockSeconds - root.screensaverSeconds) * 1000)
    repeat: false
    onTriggered: if (root.inCycle) root.lockNow()
  }

  property Timer suspendTimer: Timer {
    interval: Math.max(0, (root.suspendSeconds - root.screensaverSeconds) * 1000)
    repeat: false
    onTriggered: if (root.inCycle) root.suspendIfOnBattery()
  }
}
