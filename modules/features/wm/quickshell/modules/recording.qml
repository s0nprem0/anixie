import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// The record dot: a camera in the bar while a screen recording runs, and nothing
// at all while one does not.
//
// It is loaded from bar.json as a `type: "qml"` module, which is why it lives in
// modules/ rather than in components/ — those are reached through the id registry,
// and this one is meant to be droppable without touching it.
//
// State is polled rather than signalled. A recording is started by a Hyprland
// bind, stopped by that same bind, by this button, or by `record --stop` from a
// shell, so there is no one place to hook onto. `record --status` is a cheap
// question — it reads a pid file and checks that the process is still a recorder —
// and it is the same answer the stop path uses, so the bar cannot disagree with
// what a stop would do.
BarWidget {
  id: root

  property bool recording: false

  // Often enough that a recording started from the keyboard shows up promptly,
  // rare enough not to be worth noticing. The click path re-queries directly, so
  // stopping never waits for a tick.
  readonly property int pollMs: 1500

  visible: root.recording
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout

    anchors.centerIn: parent
    text: Util.record
    active: true
    activeColor: Theme.danger
    tooltipText: "Recording · click to stop"

    onPressed: function () {
      // A Process of this module's own, the same shape as the status query below,
      // and not `bar.run`.
      //
      // `bar.run` is the documented way for a drop-in module to run something, and
      // it is what this used at first — but the bar's handle is handed to a module
      // *after* it loads, and only if the module already has a `bar` property.
      // Without one the assignment is skipped, `bar` is undefined, and the click
      // threw "Cannot read property 'run' of undefined" every time: a stop button
      // that looked right, sat in the bar, and did nothing at all.
      //
      // Running the command directly has no such gap, and it is the mechanism
      // already proven here — the status query spawns `record` the same way on
      // every tick.
      stopQuery.running = true
    }
  }

  Process {
    id: stopQuery
    command: ["record", "--stop"]
    // The dot is cleared by the status query rather than here, so it reflects
    // whether the recorder is really gone instead of whether the stop returned.
    onExited: function () { statusQuery.running = true }
  }

  Process {
    id: statusQuery
    command: ["record", "--status"]
    // Exit 0 means a recorder of ours is up. Anything else — a stale pid, no pid
    // file, the command missing — is "not recording", which is the safe reading:
    // a dot that never appears is a smaller problem than one that will not go away.
    onExited: function (exitCode) { root.recording = exitCode === 0 }
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusQuery.running = true
  }
}
