pragma Singleton

pragma ComponentBehavior: Bound
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
// logind listener handles the pre-suspend lock and the post-resume DPMS, so the
// old hypridle service is gone entirely.
//
// Timings follow the previous idle config, with a visual screensaver in the gap
// before the display blanked: screensaver at 2.5 minutes, display off at 5, lock
// at 10, and suspend at 30 on battery only. `respectInhibitors` keeps the
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

  readonly property string statePath: {
    const xdg = Quickshell.env("XDG_STATE_HOME")
    const home = Quickshell.env("HOME")
    const base = (xdg && String(xdg).trim() !== "")
      ? String(xdg)
      : ((home && String(home).trim() !== "")
          ? String(home) + "/.local/state"
          : "/tmp")
    return base + "/anixie/idle"
  }

  readonly property string stateDir: {
    const path = root.statePath
    const idx = path.lastIndexOf("/")
    return idx > 0 ? path.slice(0, idx) : "/tmp"
  }

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

    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    root.pushIndicator()
    Qt.callLater(root.onIdleChanged)
  }

  function remember(value) {
    try {
      root.stateFile.setText(value ? "on\n" : "off\n")
    } catch (e) {
      console.warn("idle: could not persist state")
    }
  }

  function pushIndicator() {
    IndicatorHost.setIdle(root.enabled ? "on" : "off")
  }

  // Stop the screensaver and its timers without touching the display-blanked
  // state or the pending suspend deadline.
  function stopScreensaverAndTimers() {
    root.screensaverShown = false
    root.inCycle = false
    blankTimer.stop()
    lockTimer.stop()
  }

  // Cancel the whole idle period, including any pending suspend.
  function cancelIdlePeriod() {
    root.stopScreensaverAndTimers()
    suspendTimer.stop()
  }

  // Locking cleans up the screensaver and blank timer but deliberately leaves
  // the suspend deadline in place.
  function handleLock() {
    root.screensaverShown = false
    blankTimer.stop()
    lockTimer.stop()
    // Keep inCycle true so the suspend timer remains meaningful.
    root.inCycle = true
  }

  function applyEnabled(value) {
    root.enabled = !!value
    root.pushIndicator()
    if (!root.enabled) {
      root.cancelIdlePeriod()
      root.recoverDisplay()
    }
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

  function recoverDisplay() {
    if (!root.displayBlanked) return
    root.displayBlanked = false
    root.dpmsToken += 1
    root.wakeDpms.token = root.dpmsToken
    root.dpms("off")
    root.wakeDpms.restart()
  }

  function wake() {
    root.cancelIdlePeriod()
    root.recoverDisplay()
  }

  property int dpmsToken: 0

  property Timer wakeDpms: Timer {
    interval: 200
    repeat: false
    property int token: 0
    onTriggered: {
      if (root.wakeDpms.token !== root.dpmsToken) return
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

  function startCycle() {
    if (root.inCycle) return

    root.inCycle = true
    root.screensaverShown = true
    root.displayBlanked = false
    blankTimer.restart()
    lockTimer.restart()
    suspendTimer.restart()
  }

  function lockNow() {
    if (LockHost.locked) return
    root.handleLock()
    LockHost.lock()
  }

  function lockAndSuspend() {
    root.cancelIdlePeriod()
    LockHost.lockAndSuspend()
  }

  function suspendIfOnBattery() {
    if (!UPower.onBattery) return
    // Execute only once: stop the cycle before triggering suspend.
    root.inCycle = false
    root.screensaverShown = false
    blankTimer.stop()
    lockTimer.stop()
    suspendTimer.stop()
    LockHost.lockAndSuspend()
  }

  // ---- the cycle ----

  property IdleMonitor idleMonitor: IdleMonitor {
    enabled: root.enabled && !LockHost.locked
    timeout: Math.max(1, root.screensaverSeconds)
    respectInhibitors: true
    onIsIdleChanged: root.onIdleChanged()
  }

  property Connections lockWatch: Connections {
    target: LockHost
    function onLockedChanged() {
      if (LockHost.locked) root.handleLock()
      else {
        root.recoverDisplay()
        Qt.callLater(root.onIdleChanged)
      }
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