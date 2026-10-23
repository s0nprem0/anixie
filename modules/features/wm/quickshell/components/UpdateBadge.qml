import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// A badge while the configuration is newer than the system that is running it.
//
// Omarchy's equivalent is its update arrow: a release exists, click it and the
// update runs. A flake has no releases to wait for — what it has is a tree that
// changes, and a system profile that was built from an earlier state of it. So
// the comparison here is the two timestamps that actually answer the question:
// when the last commit landed, and when the running system was activated.
//
// Which makes it honest about a different thing, and a more useful one on a
// machine that is edited rather than installed: it says "what is in the repo is
// not what you are running", whether that is a new package, a fixed panel, or a
// setting changed an hour ago.
BarWidget {
  id: root

  // Where the tree is. The rebuild aliases use the same place, from NH_FLAKE.
  readonly property string repo: String(root.setting("repo", Quickshell.env("HOME") + "/nix-dots"))
  readonly property int interval: Number(root.setting("interval", 300)) * 1000

  property double systemTime: 0
  property double commitTime: 0

  // A minute of slack: the commit is written first and the build finishes later,
  // and a badge that appears during every rebuild would be right and useless.
  readonly property bool pending: root.commitTime > root.systemTime + 60

  function refresh() {
    probe.running = false
    probe.running = true
  }

  Process {
    id: probe
    command: ["sh", "-c", "stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || echo 0; git -C \"$1\" log -1 --format=%ct 2>/dev/null || echo 0", "_", root.repo]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(this.text).trim().split("\n")
        root.systemTime = Number(lines[0]) || 0
        root.commitTime = Number(lines[1]) || 0
      }
    }
  }

  readonly property Timer watch: Timer {
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  wantsSlot: root.pending
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.update
    labelText: ""
    active: true
    // Warning rather than accent: a system that is not the one you configured is
    // a thing to notice, not a mode to be in.
    foreground: Theme.danger
    activeColor: Theme.danger
    tooltipText: "This tree is newer than the running system · click to rebuild"

    onPressed: function () {
      Commands.app("kitty", ["-e", "anixie", "update"])
    }
  }
}