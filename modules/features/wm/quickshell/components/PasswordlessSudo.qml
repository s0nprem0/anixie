import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// The key, lit while sudo takes no password.
//
// On this machine it always is: `wheelNeedsPassword = false` puts NOPASSWD on the
// wheel group, and `son` is in wheel. So this is not a warning about something
// that went wrong — it is the standing statement that anyone who can reach this
// session already has root, which is the thing to remember when a laptop travels
// somewhere else. The reference shell shows the same thing for the same reason,
// and hides it when it is off.
//
// A click opens visudo rather than toggling anything. Changing sudo is an edit of
// a root file and a deliberate act, not a state to flip from a panel: sudoers has
// to stay parseable or the machine locks you out, which is what visudo's check
// before it writes is for.
BarWidget {
  id: root

  property bool passwordless: false

  readonly property string status: root.passwordless
    ? "Sudo needs no password · click to edit"
    : "Sudo asks for a password"

  // Read once, and re-read when asked. Nothing here changes on a timer — sudo is
  // decided when the system is built — so a poll would be the bar asking the same
  // question every few seconds for an answer that can only change by a rebuild.
  Process {
    id: probe
    command: ["passwordless-sudo"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.passwordless = this.text.trim() === "on"
    }
  }

  function refresh() {
    probe.running = false
    probe.running = true
  }

  // Shown only while it is true, so on a machine where sudo does ask, this costs
  // the bar nothing.
  visible: root.passwordless

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.key
    labelText: ""
    tooltipText: root.status
    active: true
    // Urgent rather than accent: this one is about how much the session is worth
    // to anyone who reaches it, and it should not sit there in the same colour as
    // a chosen workspace.
    foreground: Theme.danger
    activeColor: Theme.danger
    selected: true
    onPressed: function () { Commands.run("passwordless-sudo edit") }
  }
}