pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Io

// A badge while the configuration is newer than the system that is running it.
//
// The comparison is a timestamp heuristic, not proof of build identity: the
// running system does not expose its source revision in a form this shell can
// read, and a commit timestamp is not a reliable ordering key across rebases
// or clock skew. The badge therefore says "the tree differs from the running
// system", which is the honest claim, and never "the repository is newer".
BarWidget {
  id: root

  readonly property string repo: {
    const configured = String(root.setting("repo", ""))
    if (configured !== "") return configured
    const home = Quickshell.env("HOME")
    return (home && home !== "") ? home + "/anixie" : ""
  }

  readonly property int intervalMs: {
    const raw = Number(root.setting("interval", 300))
    if (!Number.isFinite(raw) || raw <= 0) return 300000
    return Math.max(30000, Math.min(Math.round(raw * 1000), 3600000))
  }

  property double systemTime: 0
  property double commitTime: 0
  property bool dirty: false
  property bool probeOk: false

  property double lastSystemTime: 0
  property double lastCommitTime: 0
  property bool lastDirty: false
  property bool lastProbeOk: false

  property int probeToken: 0
  property int activeProbeToken: -1

  readonly property bool pending: root.lastProbeOk
    && (root.lastDirty || root.lastCommitTime > root.lastSystemTime + 60)

  function refresh() {
    if (probe.running) return

    root.probeToken = (root.probeToken + 1) % 1000000
    const token = root.probeToken
    root.activeProbeToken = token
    probe.token = token
    probe.command = [
      "sh", "-c",
      "repo=\"$1\"; [ -d \"$repo/.git\" ] || exit 2; " +
      "st=$(stat -c %Y /nix/var/nix/profiles/system 2>/dev/null) || exit 3; " +
      "ct=$(git -C \"$repo\" log -1 --format=%ct 2>/dev/null) || exit 4; " +
      "dirty=0; git -C \"$repo\" diff --quiet 2>/dev/null || dirty=1; " +
      "git -C \"$repo\" diff --cached --quiet 2>/dev/null || dirty=1; " +
      "printf '%s\\n%s\\n%s\\n' \"$st\" \"$ct\" \"$dirty\"",
      "_", root.repo
    ]
    probe.running = true
  }

  Process {
    id: probe
    property int token: -1

    stdout: StdioCollector {
      onStreamFinished: probe.collected = this.text
    }

    property string collected: ""

    onExited: function (exitCode, exitStatus) {
      if (probe.token !== root.activeProbeToken) return
      if (exitCode !== 0) {
        root.probeOk = false
        return
      }
      const lines = String(probe.collected || "").trim().split("\n")
      if (lines.length < 3) {
        root.probeOk = false
        return
      }
      const st = Number(lines[0])
      const ct = Number(lines[1])
      const dirtyFlag = lines[2].trim() === "1"
      if (!Number.isFinite(st) || !Number.isFinite(ct)) {
        root.probeOk = false
        return
      }
      root.systemTime = st
      root.commitTime = ct
      root.dirty = dirtyFlag
      root.probeOk = true
      root.lastSystemTime = st
      root.lastCommitTime = ct
      root.lastDirty = dirtyFlag
      root.lastProbeOk = true
    }
  }

  readonly property Timer watch: Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property bool launching: false

  wantsSlot: root.pending
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.update
    labelText: ""
    active: true
    foreground: Theme.danger
    activeColor: Theme.danger
    tooltipText: root.pending
      ? (root.lastDirty
          ? "Uncommitted changes are newer than the running system · click to rebuild"
          : "This tree differs from the running system · click to rebuild")
      : "Up to date"

    onPressed: function () {
      if (root.launching) return
      root.launching = true
      Commands.app("kitty", ["-e", "anixie", "update"])
      launchGuard.restart()
    }
  }

  property Timer launchGuard: Timer {
    interval: 3000
    repeat: false
    onTriggered: root.launching = false
  }
}