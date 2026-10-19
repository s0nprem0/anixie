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
// the shell running the check itself.
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
    command: ["sh", "-c", "ps -eo comm= | grep -cE '^(claude|opencode|codex)$' || true"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.sessions = Number(String(this.text).trim()) || 0
    }
  }

  Timer {
    interval: 3000
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