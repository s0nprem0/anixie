import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// The laptop, lit while someone is logged in from somewhere else.
//
// logind is the source, not any one remote program: no remote desktop is
// installed here, and the thing worth knowing is not which tool connected but
// that the machine has a second session on it. SSH would show up here too.
//
// Shown only while it is true, and never polled — a session appears and goes
// with a login and a logout, and the two loginctl calls below are cheap enough to
// run on a slow timer rather than assume they cannot miss something.
BarWidget {
  id: root

  property bool remote: false

  // A remote login is rare and not urgent to the second, so this is a slow timer
  // rather than a fast one. The module is built even while it is hidden — a
  // Repeater builds every entry in the section — so the cost is paid either way,
  // and two loginctl calls a minute is a cost worth paying; five seconds apart
  // forever is not.
  readonly property int interval: Number(root.setting("interval", 30000))

  Process {
    id: probe
    command: ["remote-session"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.remote = this.text.trim() === "remote"
    }
  }

  // Restarted rather than left running: a Process runs once and stops, so
  // re-arming it is how it is asked again. Both assignments, or a Process that
  // has already exited will not re-run from `true` alone.
  function refresh() {
    probe.running = false
    probe.running = true
  }

  readonly property Timer watch: Timer {
    interval: root.interval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  visible: root.remote
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.laptop
    labelText: ""
    tooltipText: root.remote
      ? "A remote session is logged in · click to see who"
      : "No remote session"
    active: true
    // The same urgent colour as the sudo key: both say the machine is reachable
    // by someone, which is the one idea they share.
    foreground: Theme.danger
    activeColor: Theme.danger
    selected: true
    onPressed: function () {
      Commands.run("list=$(remote-session list); notify-send -a sessions 'Login sessions' \"$list\"")
    }
  }
}