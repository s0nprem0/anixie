pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop background: one file path shared by every output.
//
// The `wallpaper` command decides what the path is and writes it here, then
// tells this object over IPC so a running shell crossfades immediately. The file
// is what a shell that starts later reads, which matters at login: the theme
// service and the shell both start at graphical-session.target, so either can
// win the race.
//
// The image itself is drawn by BackgroundSurface, one per output.
QtObject {
  id: root

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/theme/background"

  property string path: ""

  // Bumped whenever the chosen file changes, including a theme that rewrites
  // the generated wallpaper at the same path. The surface uses it to reload a
  // file whose name did not change.
  property int revision: 0

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: root.adopt(root.stateFile.text())
    onFileChanged: root.stateFile.reload()
  }

  // At login the file may not exist yet. Retry for a while rather than leave the
  // fallback gradient up until the next theme switch; once a path arrives the
  // timer stops for good.
  property int attempts: 0

  property Timer settle: Timer {
    interval: 500
    repeat: true
    running: root.path === "" && root.attempts < 60
    onTriggered: {
      root.attempts += 1
      root.stateFile.reload()
    }
  }

  function adopt(raw) {
    const value = String(raw || "").trim()
    if (value === "" || value === root.path) return

    root.path = value
    root.revision += 1
  }

  // Called from the wallpaper command over IPC, and the alternative to editing
  // the file by hand. Writing the file as well means the choice survives a shell
  // restart even when the caller was not the wallpaper command.
  function set(path) {
    const value = String(path || "").trim()
    if (value === "") return

    root.path = value
    root.revision += 1
    root.stateFile.setText(value + "\n")
  }

  function reload() {
    root.stateFile.reload()
  }
}
