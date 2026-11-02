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
// The state lives in the shell (RecorderHost) and `record` pushes it in when a
// recording starts or stops. It used to be asked for: `record --status` every
// 1.5 seconds, which is a 456-line bash script parsed twice a second to answer a
// question whose answer changes twice a day. That was about 4% of a core, spent
// drawing a dot that is absent almost all of the time.
//
// The push is what makes this work from every entry point — a Hyprland bind,
// this button, or `record --stop` from a shell — because the one thing they all
// have in common is that they run `record`, which is what reports the change.
BarWidget {
  id: root

  readonly property bool recording: RecorderHost.recording

  // `wantsSlot`, not `visible`: the bar lays out Loaders, and a Loader measures
  // what it loaded whether or not it is drawn. A module that hid itself with
  // `visible` left a gap the size of a camera in the bar all day.
  wantsSlot: root.recording
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
      // A Process of this module's own, and not `bar.run`.
      //
      // `bar.run` is the documented way for a drop-in module to run something, and
      // it is what this used at first — but the bar's handle is handed to a module
      // *after* it loads, and only if the module already has a `bar` property.
      // Without one the assignment is skipped, `bar` is undefined, and the click
      // threw "Cannot read property 'run' of undefined" every time: a stop button
      // that looked right, sat in the bar, and did nothing at all.
      //
      // Running the command directly has no such gap.
      stopQuery.running = true
    }
  }

  // The dot is not cleared here. `record --stop` reports the change itself, once
  // the recorder is really gone, so the dot follows the recorder rather than the
  // click — which is the same reason the old version re-queried after stopping
  // instead of trusting the stop to have worked.
  Process {
    id: stopQuery
    command: ["record", "--stop"]
  }
}