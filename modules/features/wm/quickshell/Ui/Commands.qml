pragma Singleton

import QtQuick
import Quickshell.Io

// Fire-and-forget shell commands, in one place so modules do not each grow their
// own Process and have to remember to keep it alive.
//
// A Process whose QML object is collected takes its child process down with it,
// so the running ones are held here until they exit — otherwise a module that
// spawns on every click would either leak or kill its own child at random.
QtObject {
  id: root

  property var running: []

  // A command line run through the shell. Quote anything interpolated into it
  // with Util.shellQuote, or use runQuoted below, which does that for you.
  function run(command) {
    const line = String(command || "").trim()
    if (line === "") return

    const source = "import Quickshell.Io; Process { running: true; command: [\"sh\", \"-c\", " + JSON.stringify(line) + "] }"
    const proc = Qt.createQmlObject(source, root, "Commands.run")
    if (!proc) return

    root.running.push(proc)

    proc.onExited.connect(function () {
      const index = root.running.indexOf(proc)
      if (index !== -1) root.running.splice(index, 1)
      proc.destroy()
    })
  }

  // A user-facing application, launched through the UWSM scope helper. Use
  // this for anything with a window or a tray icon, so systemd owns a unit for
  // it rather than it living in the compositor's cgroup. Short tools and IPC
  // calls stay on run/runQuoted.
  function app(binary, args) {
    root.runQuoted("app-launch", [String(binary)].concat(args || []))
  }

  // A binary and its arguments, each quoted individually. The right shape for
  // anything taking a window title or other text that may contain spaces and
  // quotes, where a hand-built command line is a quoting bug waiting to happen.
  function runQuoted(binary, args) {
    const parts = [Util.shellQuote(binary)]

    const list = args || []
    for (let i = 0; i < list.length; i++) parts.push(Util.shellQuote(list[i]))

    root.run(parts.join(" "))
  }
}
