pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Whether a screen recording is running.
//
// The shell holds this rather than asking for it. Checking whether a
// recorder is running is a cheap question in itself, but the bar
// would have to ask it every 1.5 seconds: about 4% of a core,
// continuously, for a boolean that changes twice a day. A status
// bar should not cost that to draw a dot.
//
// So the command that changes the state says so, the way `toggle dnd` already
// tells the shell about the notification state, and the shell remembers it. The
// one process left is at startup, to catch a recording that began before the
// shell did — a shell restarted mid-recording should still show the dot.
QtObject {
  id: root

  property bool recording: false

  function set(value) {
    root.recording = !!value
  }

  // The single ask, at load: `record --status` answers with a word,
  // not an exit code, so the answer is parsed from stdout. Anything
  // else — a stale pid, no pid file, the command missing — is "not
  // recording", which is the safe reading: a dot that never appears
  // is a smaller problem than one that will not go away.
  property Process startupQuery: Process {
    command: ["record", "--status"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: { root.recording = String(this.text || "").trim() === "recording" }
    }
  }
}