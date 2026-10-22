import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../Ui"

// Dropbox: whether the daemon is running, and the files it touched most
// recently.
//
// Dropbox has no status API beyond its own CLI, and no machine-readable storage
// figure at all, so this reports what can be verified: the daemon's state and a
// short recent-files list from the sync folder. The widget hides when `dropbox`
// is not installed, which keeps it out of the way on machines that never opted
// in.
BarWidget {
  id: root

  Component.onCompleted: {
    PanelRegistry.register("dropbox", readout, panel)
    which.running = true
  }

  readonly property int intervalMs: Math.max(5000, Number(root.setting("interval", 30)) * 1000)
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string folder: {
    const configured = String(root.setting("folder", ""))
    return configured !== "" ? configured : root.home + "/Dropbox"
  }

  property bool installed: false
  property bool running: false
  property bool busy: false
  property string statusText: ""
  property var recent: []
  property string lastError: ""

  function refresh() {
    if (!root.installed || status.running) return
    status.running = false
    status.running = true
  }

  function refreshSoon() {
    root.busy = true
    root.refreshTimer.restart()
  }

  function startStop() {
    Commands.runQuoted("dropbox", [root.running ? "stop" : "start"])
    root.refreshSoon()
  }

  function loadRecent() {
    if (!root.installed || recentFiles.running) return
    recentFiles.running = true
  }

  function open(path) {
    if (String(path) !== "") Commands.runQuoted("xdg-open", [String(path)])
  }

  function applyStatus(text, error) {
    root.statusText = String(text || "").trim().split("\n")[0]
    root.lastError = String(error || "").trim().split("\n")[0]
    root.running = root.statusText !== "" && !/not running/i.test(root.statusText)
  }

  function applyRecent(text) {
    const out = []
    for (const raw of String(text || "").split("\n")) {
      const tab = raw.indexOf("\t")
      if (tab <= 0) continue

      const stamp = Number(raw.slice(0, tab))
      const path = raw.slice(tab + 1)
      if (!isFinite(stamp) || path === "") continue

      const parts = path.split("/")
      out.push({
        path: path,
        name: parts.length > 0 ? parts[parts.length - 1] : path,
        stamp: stamp,
      })
    }
    root.recent = out
  }

  function ago(stamp) {
    const seconds = Math.max(0, Math.floor(Date.now() / 1000 - Number(stamp)))
    if (seconds < 60) return "just now"
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"
    const days = Math.floor(hours / 24)
    if (days < 7) return days + "d ago"
    return new Date(Number(stamp) * 1000).toLocaleDateString()
  }

  readonly property string stateLabel: root.running
    ? (root.statusText !== "" ? root.statusText : "Running")
    : (root.installed ? "Stopped" : "Not installed")

  wantsSlot: root.installed
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  Process {
    id: which
    running: false
    command: ["sh", "-c", "command -v dropbox"]

    stdout: StdioCollector {
      onStreamFinished: {
        root.installed = String(this.text).trim() !== ""
        if (root.installed) root.refresh()
      }
    }
  }

  Process {
    id: status
    running: false
    command: ["dropbox", "status"]

    // `dropbox status` exits nonzero when it is not running, and the useful
    // text is usually on stderr. Applying from both collectors and again on
    // exit means the last stream to arrive is the one that decides, without
    // depending on Qt's ordering between them.
    stdout: StdioCollector {
      id: statusOut
      onStreamFinished: root.applyStatus(statusOut.text, statusErr.text)
    }
    stderr: StdioCollector {
      id: statusErr
      onStreamFinished: root.applyStatus(statusOut.text, statusErr.text)
    }
    onExited: root.applyStatus(statusOut.text, statusErr.text)
  }

  Process {
    id: recentFiles
    running: false
    command: ["sh", "-c",
      'find "$1" -maxdepth 5 -type f -printf "%T@\\t%p\\n" 2>/dev/null'
      + ' | sort -nr | head -n 8',
      "_", root.folder]

    stdout: StdioCollector {
      onStreamFinished: root.applyRecent(this.text)
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.installed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 1800
    repeat: false
    onTriggered: {
      root.busy = false
      root.refresh()
    }
  }

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.dropbox
    active: root.running
    tooltipText: "Dropbox · " + root.stateLabel + " · click for files"

    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) PanelRegistry.toggle("dropbox", readout)
      else if (button === Qt.RightButton) root.refresh()
    }
  }

  Component {
    id: panel

    Panel {
      id: card
      title: ""

      Component.onCompleted: root.loadRecent()

      PanelHero {
        width: card.contentWidth
        glyph: Util.dropbox
        title: "Dropbox"
        subtitle: root.stateLabel
      }

      PanelSeparator {}

      PanelActionButton {
        width: card.contentWidth
        label: root.busy ? "Working…" : (root.running ? "Stop Dropbox" : "Start Dropbox")
        navigational: false
        outlined: root.running
        available: !root.busy
        onClicked: root.startStop()
      }

      PanelActionButton {
        width: card.contentWidth
        label: "Open Dropbox folder"
        value: root.folder
        onClicked: root.open(root.folder)
      }

      PanelActionButton {
        width: card.contentWidth
        label: "Refresh"
        navigational: false
        available: !root.busy
        onClicked: root.refresh()
      }

      PanelSeparator {
        visible: root.recent.length > 0
      }

      PanelSectionHeader {
        width: card.contentWidth
        visible: root.recent.length > 0
        label: "Recent files"
      }

      Text {
        width: card.contentWidth
        height: implicitHeight
        visible: root.recent.length === 0
        text: root.lastError !== ""
          ? root.lastError
          : "No recent files in " + root.folder
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.recent

        delegate: PanelActionButton {
          id: recentRow
          required property var modelData

          width: card.contentWidth
          label: recentRow.modelData.name
          value: root.ago(recentRow.modelData.stamp)
          navigational: false
          onClicked: root.open(recentRow.modelData.path)
        }
      }
    }
  }
}
