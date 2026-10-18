pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Notification history, kept on disk so it outlives the shell.
//
// The daemon holds a notification only while it is on screen; once it expires,
// is dismissed, or its action runs, the client is gone and there is nothing left
// to ask about it. That is the whole reason history used to be lost: nothing
// was copied down.
//
// So each notification is mirrored to its own single-line JSON file for as long
// as it is on screen, and that file is *moved* into history/ when the
// notification goes away. History is therefore just the set of archived files,
// which means it survives a shell restart — reloading the bar while editing it
// no longer empties the list.
//
// One file per notification rather than one JSON array, so a half-finished write
// costs at most a single entry instead of the whole history, and so archiving
// is a rename rather than a rewrite of everything.
//
// Files are written through `sh -c` with the JSON passed as an argv element,
// not as a shell string and not on stdin: it reaches the process untouched, so
// nothing in a title or a body can turn into shell syntax.
QtObject {
  id: root

  // XDG_STATE_HOME is where state belongs; HOME/.local/state is the fallback the
  // specification gives for when it is unset.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/quickshell/notifications"
  readonly property string liveDir: root.stateDir + "/live"
  readonly property string historyDir: root.stateDir + "/history"

  // Bounded because nothing collects the files on its own, and a list nobody
  // scrolls to the end of is not worth unbounded disk.
  readonly property int historyLimit: 50

  // Newest first. Empty until something reads the directory, so the panel reads
  // on demand rather than the daemon holding a copy nothing else needs.
  property var entries: []

  // Which live file belongs to which notification id, so a change in the tracked
  // list can be turned into an archive. The id alone is not enough: file names
  // carry the timestamp too, and ids are reused by later notifications.
  property var live: ({})

  // ---- commands ----

  function writeCommand(dir, name, line) {
    return ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/$3"', "_", dir, line, name]
  }

  // Archive and prune in one invocation: the move, then drop anything past the
  // limit with the newest kept. Sorting by modification time rather than by
  // name, because the names encode the same instant but `ls -t` does not care
  // that they were written in that order.
  function archiveCommand(name) {
    return ["sh", "-c",
      'mkdir -p "$2" && mv -f "$1/$3" "$2/$3"'
      + ' && cd "$2" && ls -1t -- *.json 2>/dev/null'
      + ' | tail -n +$(( $4 + 1 )) | xargs -r rm -f --',
      "_", root.liveDir, root.historyDir, name, String(root.historyLimit)]
  }

  function readCommand(dir) {
    return ["sh", "-c", 'cat "$1"/*.json 2>/dev/null', "_", dir]
  }

  function clearCommand() {
    return ["sh", "-c", 'rm -f -- "$1"/*.json', "_", root.historyDir]
  }

  // Sweep away popups the shell did not survive.
  //
  // A notification is only archived when it drops out of the daemon's tracked
  // list, and that list lives in memory — so anything still on screen when the
  // shell died is left behind in live/ with nothing left to move it. Reaped at
  // startup, where the memory is gone anyway.
  //
  // Only files older than two minutes: a reload keeps the process alive and
  // re-runs this, and its popups are still on screen and still legitimately
  // live. A popup lives for seconds, so two minutes is comfortably past any of
  // them.
  function reapCommand() {
    return ["sh", "-c",
      'mkdir -p "$2"'
      + ' && find "$1" -maxdepth 1 -name "*.json" -mmin +2 -exec mv -f -- {} "$2"/ \; 2>/dev/null'
      + '; cd "$2" && ls -1t -- *.json 2>/dev/null | tail -n +$(( $3 + 1 )) | xargs -r rm -f --',
      "_", root.liveDir, root.historyDir, String(root.historyLimit)]
  }

  Component.onCompleted: root.enqueue(root.reapCommand())

  // ---- worker pool ----
  //
  // Every command is a short `sh -c`, and more than one can be wanted at once (a
  // notification arriving while another is being archived). A Process runs one
  // command at a time, so they go through a queue drained by a small pool — big
  // enough not to serialise a burst of notifications, small enough not to leave
  // processes lying about.

  readonly property int workerCount: 3

  function workerAt(index) {
    if (index === 0) return root.workerA
    if (index === 1) return root.workerB
    return root.workerC
  }

  property var queue: []

  function enqueue(command, collect) {
    root.queue = root.queue.concat([{ command: command, collect: !!collect }])
    root.pump()
  }

  function pump() {
    for (let i = 0; i < root.workerCount && root.queue.length > 0; i++) {
      const worker = root.workerAt(i)
      if (!worker || worker.running || worker.task !== null) continue

      const task = root.queue[0]
      root.queue = root.queue.slice(1)
      worker.task = task
      worker.collecting = task.collect
      worker.command = task.command
      worker.running = true
    }
  }

  component Worker: Process {
    id: worker

    property var task: null

    // Set only while this worker's command is one whose output is wanted, so the
    // text of an archival `mv` is never mistaken for the history listing.
    property bool collecting: false

    stdout: StdioCollector {
      onStreamFinished: if (worker.collecting) root.onOutput(this.text)
    }

    onExited: {
      worker.task = null
      worker.collecting = false
      root.pump()
    }
  }

  property Worker workerA: Worker {}
  property Worker workerB: Worker {}
  property Worker workerC: Worker {}

  // One file per notification, so concatenating them gives one JSON object per
  // line. A line that will not parse is a torn write from a crash mid-save: it
  // is dropped and the rest of the history is kept.
  function parse(text) {
    const out = []
    for (const line of String(text || "").split("\n")) {
      const trimmed = line.trim()
      if (!trimmed) continue
      try {
        const value = JSON.parse(trimmed)
        if (value && typeof value === "object") out.push(value)
      } catch (e) {
      }
    }
    out.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0))
    return out
  }

  // ---- use ----

  // Mirror a notification that has just arrived.
  //
  // Recorded even while silenced: silencing means "do not interrupt me", not
  // "pretend it never happened", and history is exactly where a muted
  // notification is looked for afterwards.
  function begin(notification) {
    if (!notification) return

    const key = String(notification.id)
    const stamp = Date.now()
    const name = stamp + "-" + key + ".json"

    // A client reusing an id through replaces_id is updating a notification it
    // already sent. Archive the earlier file rather than leaving two entries for
    // one notification.
    const previous = root.live[key]
    if (previous) root.enqueue(root.archiveCommand(previous))

    root.live[key] = name
    root.enqueue(root.writeCommand(root.liveDir, name, root.snapshot(notification, stamp)))
  }

  // Archive everything no longer on screen. Called with the ids the daemon still
  // holds, which is the only thing that can tell a notification has ended — the
  // client may have closed it itself, with no call of ours to hook.
  function sweep(liveIds) {
    const stillLive = {}
    for (const id of liveIds) {
      const name = root.live[String(id)]
      if (name) stillLive[name] = true
    }

    const gone = {}
    for (const id in root.live) {
      const name = root.live[id]
      if (!stillLive[name]) gone[id] = name
    }

    for (const id in gone) {
      delete root.live[id]
      // Deliberately not collected: this command's output is `ls` and `rm`, not
      // history. Parsing it as JSON would replace the list with nothing every
      // time a notification expired.
      root.enqueue(root.archiveCommand(gone[id]))
    }
  }

  function refresh() {
    root.enqueue(root.readCommand(root.historyDir), true)
  }

  // Only the directory read collects output. Every other command's stdout is its
  // own noise — file names, `ls`, nothing at all — and handing that to the
  // parser would throw away a good list.
  function onOutput(text) {
    root.entries = root.parse(text)
  }

  function clear() {
    root.entries = []
    root.enqueue(root.clearCommand())
  }

  // Actions are deliberately not carried over: they are closures into the
  // sending client's process, which is gone by the time the notification reaches
  // history. A row offering a button that cannot work would be worse than none.
  function snapshot(notification, stamp) {
    return JSON.stringify({
      id: notification.id,
      app: String(notification.appName || ""),
      appIcon: String(notification.appIcon || ""),
      summary: String(notification.summary || ""),
      body: String(notification.body || ""),
      image: String(notification.image || ""),
      urgency: notification.urgency,
      timestamp: stamp
    })
  }
}