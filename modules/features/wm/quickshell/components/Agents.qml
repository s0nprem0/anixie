import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// The agent, while one is working on this machine.
//
// Omarchy has an agents widget for the AI CLI it ships with: usage, subscriptions
// and a launch button. There is no local answer to "how much of the plan is
// left" — that lives behind each vendor's account — so this answers the part that
// can be answered honestly: an agent is running right now, how many, and here is
// how to start another. It shows only while one is up, which is the same rule the
// recording dot follows, and for the same reason: a permanent glyph for something
// that is usually not happening is noise.
//
// Counted by process name rather than with `pgrep -f`, whose pattern would match
// the shell running the check itself. `ps -C` does that matching itself, so this
// is one process every five seconds rather than a shell pipeline whose grep is
// also a process.
BarWidget {
  id: root

  readonly property string launcher: String(root.setting("command", "opencode"))

  property int sessions: 0

  function refresh() {
    probe.running = false
    probe.running = true
  }

  Process {
    id: probe
    command: ["ps", "-C", "claude,opencode,codex", "-o", "comm="]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const names = String(this.text).split("\n")
        let count = 0
        for (let i = 0; i < names.length; i++) {
          if (names[i].trim() !== "") count++
        }
        root.sessions = count
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  wantsSlot: root.sessions > 0
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.agents
    labelText: root.vertical ? "" : String(root.sessions)
    active: true
    tooltipText: root.sessions
      + (root.sessions === 1 ? " agent session" : " agent sessions")
      + " · click to start another"
    onPressed: function () {
      Commands.runQuoted("kitty", ["-e", root.launcher])
    }
  }
}