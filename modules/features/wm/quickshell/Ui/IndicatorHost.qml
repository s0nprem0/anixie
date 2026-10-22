pragma Singleton

import QtQuick
import Quickshell.Io

// The state behind the bar's indicators that live outside the shell: the night
// light, the idle lock, and the reminder count.
//
// The bar used to ask for all three every four seconds — three processes, one of
// them a bash script — to read values that change when someone runs `toggle` or
// `reminder`. Those commands now push the new value in over the `indicator` IPC
// target, the same way `toggle dnd` already tells the shell about notifications,
// so the bar holds the answer instead of asking for it.
//
// Two things still have to be asked, and say why:
//   - the stay-awake inhibitor and the reminder count are asked once at startup,
//     so a state set before the shell began is still right when it does. The idle
//     lock is pushed by IdleHost, which owns it now;
//   - the night light is re-read every 30 seconds, because hyprsunset changes the
//     temperature on its own timetable (06:00 and 21:00 profiles) with nothing
//     for the shell to hear. That one read is about 30ms every 30s.
QtObject {
  id: root

  // Kelvin as hyprsunset reports it. Identity leaves the reading at whatever it
  // was, so "warmer than neutral" is what says a tint is actually applied.
  property int nightTemperature: 0
  readonly property bool nightlight: root.nightTemperature > 0 && root.nightTemperature < 6000

  // IdleHost pushes this: false means the idle lock is on.
  property bool idleStopped: false

  // Stay awake is on while its inhibitor is running.
  property bool stayAwake: false

  property int reminderCount: 0

  // FocusHost pushes this while a focus block is running.
  property bool focusActive: false

  function setNightlight(temperature) {
    const n = parseInt(temperature, 10)
    root.nightTemperature = isFinite(n) ? n : 0
  }

  function setIdle(state) {
    root.idleStopped = String(state) === "off"
  }

  function setStayAwake(state) {
    root.stayAwake = String(state) === "on"
  }

  function setReminders(count) {
    const n = parseInt(count, 10)
    root.reminderCount = isFinite(n) && n > 0 ? n : 0
  }

  function setFocus(state) {
    root.focusActive = String(state) === "true" || String(state) === "on"
  }

  property Process nightQuery: Process {
    command: ["hyprctl", "hyprsunset", "temperature"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.setNightlight(this.text.trim())
    }
  }


  // Exit non-zero when the unit is not active, which is the "off" reading.
  property Process stayAwakeQuery: Process {
    command: ["systemctl", "--user", "is-active", "anixie-stayawake"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.stayAwake = this.text.trim() === "active"
    }
  }

  property Process reminderQuery: Process {
    command: ["sh", "-c", "reminder count 2>/dev/null || echo 0"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.setReminders(this.text.trim())
    }
  }

  // The timetable is the reason this one is polled. Cheap enough to leave on.
  property Timer nightlightWatch: Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nightQuery.running = true
  }
}
