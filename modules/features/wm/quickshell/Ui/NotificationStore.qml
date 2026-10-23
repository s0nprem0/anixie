pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "NotificationText.js" as NotificationText

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

  // Copies of images that a notification references, because the sender's own
  // file does not outlive it. Named after the JSON entry's stem, so pruning an
  // entry can remove the copy without reading the JSON.
  readonly property string imagesDir: root.stateDir + "/images"

  // Bounded because nothing collects the files on its own, and a list nobody
  // scrolls to the end of is not worth unbounded disk. The time bound is the
  // more important one: an old message is rarely what someone is looking for,
  // and keeping it is a small privacy cost.
  readonly property int historyLimit: 50
  readonly property int historyHours: 24

  // Newest first. Empty until something reads the directory, so the panel reads
  // on demand rather than the daemon holding a copy nothing else needs.
  property var entries: []

  // True once the live directory has been read into `live`. The host waits for
  // this before its one reconciliation, so a notification re-emitted by the
  // daemon is never mistaken for a leftover.
  property bool ready: false

  // Which live file belongs to which notification id, so a change in the tracked
  // list can be turned into an archive. The id alone is not enough: file names
  // carry the timestamp too, and ids are reused by later notifications.
  property var live: ({})

  // ---- images ----
  //
  // A sender's image only exists while it is live: web apps delete their scoped
  // /tmp files when they close, and an image:// URL dies with the server object.
  // So the file a snapshot references is our own copy, written under a name
  // derived from the JSON entry's stem.

  function imageStem(name) {
    return String(name || "").replace(/\.json$/, "")
  }

  // The filesystem path behind a file-backed image value, or "" for anything a
  // copy cannot capture: themed icon names, in-process image:// URLs, empty.
  function localImageFile(value) {
    let path = String(value || "")
    if (path.indexOf("file://") === 0) {
      path = path.slice(7)
      try {
        path = decodeURIComponent(path)
      } catch (e) {
      }
    }
    return path.charAt(0) === "/" ? path : ""
  }

  function imageCopy(name, notification) {
    const value = String(notification.image || "")
    const source = root.localImageFile(value)

    // Nothing to copy, and nothing that would work after the sender is gone.
    if (source === "") {
      return { path: value.indexOf("image://") === 0 ? "" : value, from: "", to: "" }
    }

    const to = root.imagesDir + "/" + root.imageStem(name) + "-image"
    return { path: to, from: source === to ? "" : source, to: to }
  }

  // ---- commands ----

  function writeCommand(dir, name, line, image) {
    if (!image || !image.from) {
      return ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/$3"', "_", dir, line, name]
    }

    return ["sh", "-c",
      'mkdir -p "$1" "$4" && printf "%s\\n" "$2" > "$1/$3" && cp -f -- "$5" "$6"',
      "_", dir, line, name, root.imagesDir, image.from, image.to]
  }

  // Overwrite a file that is already on disk, keeping its name — and so its
  // timestamp and its identity in history. The existence test is the guard
  // against an update racing the archive that moved the file away: a
  // notification that has left the screen is not brought back by a late
  // property change.
  function rewriteCommand(name, line, image) {
    const copy = image && image.from ? 'cp -f -- "$5" "$6" 2>/dev/null; ' : ""
    return ["sh", "-c",
      '[ -e "$1/$2" ] || exit 0; mkdir -p "$3"; ' + copy
      + 'printf "%s\\n" "$4" > "$1/$2"',
      "_", root.liveDir, name, root.imagesDir, line,
      image ? image.from : "", image ? image.to : ""]
  }

  // Write a notification that will never be tracked into history, and prune in
  // the same invocation. Doing it as a write followed by an archive would let
  // the second command run on another worker before the first had finished.
  function discardCommand(notification, stamp) {
    const name = stamp + "-" + String(notification.id) + ".json"
    const image = root.imageCopy(name, notification)
    const copy = image.from ? ' && cp -f -- "$6" "$7"' : ""

    return ["sh", "-c",
      'mkdir -p "$2" "$5" && printf "%s\\n" "$3" > "$2/$1"' + copy
      + ' && cd "$2" && ls -1t -- *.json 2>/dev/null'
      + ' | tail -n +$(( $4 + 1 )) | while IFS= read -r f; do rm -f -- "$f" "$5/${f%.json}-image"; done',
      "_", name, root.historyDir, root.snapshot(notification, stamp, image.path),
      String(root.historyLimit), root.imagesDir, image.from, image.to]
  }

  // Archive and prune in one invocation: the move, then drop anything past the
  // limit with the newest kept. Sorting by modification time rather than by
  // name, because the names encode the same instant but `ls -t` does not care
  // that they were written in that order. The image copy belongs to the entry,
  // so it goes when the entry does.
  function archiveCommand(name) {
    return ["sh", "-c",
      'mkdir -p "$2" && mv -f "$1/$3" "$2/$3"'
      + ' && cd "$2" && ls -1t -- *.json 2>/dev/null'
      + ' | tail -n +$(( $4 + 1 )) | while IFS= read -r f; do rm -f -- "$f" "$5/${f%.json}-image"; done',
      "_", root.liveDir, root.historyDir, name, String(root.historyLimit), root.imagesDir]
  }

  function readCommand(dir) {
    return ["sh", "-c", 'cat "$1"/*.json 2>/dev/null', "_", dir]
  }

  function clearCommand() {
    return ["sh", "-c",
      'for f in "$1"/*.json; do [ -e "$f" ] || continue'
      + '; b=${f##*/}; rm -f -- "$f" "$2/${b%.json}-image"; done',
      "_", root.historyDir, root.imagesDir]
  }

  // Drop entries older than the retention window. Called before a history read
  // rather than on a timer: the panel is the only reader, and an archive that is
  // never opened is not costing anything until it is.
  function pruneHistoryCommand() {
    return ["sh", "-c",
      'now=$(date +%s); max=$3; mkdir -p "$1"; for f in "$1"/*.json; do'
      + ' [ -e "$f" ] || continue; age=$((now - $(stat -c %Y "$f")))'
      + '; [ "$age" -le "$max" ] && continue'
      + '; b=${f##*/}; b=${b%.json}; rm -f -- "$f" "$2/$b-image"; done',
      "_", root.historyDir, root.imagesDir, String(root.historyHours * 3600)]
  }

  // Filename and contents of every live file, so the id-to-file map can be
  // rebuilt after a reload. The daemon keeps its tracked notifications across a
  // reload, but this object does not, and a notification with no mapping can
  // never be archived — or, written again, lands in history twice.
  function listLiveCommand() {
    return ["sh", "-c",
      'mkdir -p "$1" && cd "$1" || exit 0'
      + '; for f in *.json; do [ -e "$f" ] || continue'
      + '; printf "%s\\t" "$f"; cat -- "$f"; printf "\\n"; done',
      "_", root.liveDir]
  }

  // Sweep away popups the shell did not survive.
  //
  // A notification is only archived when it drops out of the daemon's tracked
  // list, and that list lives in memory — so anything still on screen when the
  // shell died is left behind in live/ with nothing left to move it. Reaped at
  // startup, where the memory is gone anyway.
  //
  // `keep` is the set of files the startup listing just mapped. They are left
  // alone even when old — a resident notification can sit on screen for hours —
  // and the remaining files still need to be older than two minutes, so a file
  // being written while this runs is not swept out from under its notification.
  function reapCommand(keep) {
    return ["sh", "-c",
      'mkdir -p "$2"'
      + '; for f in "$1"/*.json; do [ -e "$f" ] || continue'
      + '; b=${f##*/}'
      + '; case " $4 " in *" $b "*) continue ;; esac'
      + '; find "$f" -maxdepth 0 -mmin +2 -print -quit 2>/dev/null | grep -q . || continue'
      + '; mv -f -- "$f" "$2"/; done'
      + '; cd "$2" && ls -1t -- *.json 2>/dev/null | tail -n +$(( $3 + 1 ))'
      + ' | while IFS= read -r f; do rm -f -- "$f" "$5/${f%.json}-image"; done',
      "_", root.liveDir, root.historyDir, String(root.historyLimit), String(keep || ""), root.imagesDir]
  }

  // The listing runs first, and reaping is chained onto the end of it: a reaper
  // running beside the listing could move a file the map is about to claim.
  Component.onCompleted: {
    root.enqueue(root.listLiveCommand(), root.absorbLive)
    root.enqueue(root.pruneHistoryCommand())
  }

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

  function enqueue(command, handler) {
    root.queue = root.queue.concat([{ command: command, handler: handler || null }])
    root.pump()
  }

  function pump() {
    for (let i = 0; i < root.workerCount && root.queue.length > 0; i++) {
      const worker = root.workerAt(i)
      if (!worker || worker.running || worker.task !== null) continue

      const task = root.queue[0]
      root.queue = root.queue.slice(1)
      worker.task = task
      worker.handler = task.handler
      worker.command = task.command
      worker.running = true
    }
  }

  component Worker: Process {
    id: worker

    property var task: null

    // Set only while this worker's command is one whose output is wanted, so the
    // text of an archival `mv` is never mistaken for the history listing or the
    // live listing.
    property var handler: null

    stdout: StdioCollector {
      onStreamFinished: if (worker.handler) worker.handler(this.text)
    }

    onExited: {
      worker.task = null
      worker.handler = null
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

  // ---- in-place updates ----
  //
  // A client updating through replaces_id does not produce a second
  // notification signal: the server rewrites the object it already holds and
  // emits that object's property changes. So the live file is kept current by
  // watching those signals, not by waiting for another arrival.
  //
  // `watched` also holds the object, so a repeated signal cannot attach a second
  // set of handlers; `sweep` drops the entry when the notification leaves.

  property var watched: ({})
  property var pendingRewrites: ({})
  property bool rewriteQueued: false

  function watch(notification) {
    const key = String(notification.id)
    if (root.watched[key] === notification) return
    root.watched[key] = notification

    const signals = [
      "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
      "imageChanged", "urgencyChanged", "expireTimeoutChanged"
    ]
    for (const signal of signals) {
      notification[signal].connect(function () { root.queueRewrite(notification) })
    }
  }

  // One write per event-loop turn: a single update usually changes several
  // roles at once, and each has its own signal.
  function queueRewrite(notification) {
    root.pendingRewrites[String(notification.id)] = notification

    if (root.rewriteQueued) return
    root.rewriteQueued = true
    Qt.callLater(root.flushRewrites)
  }

  function flushRewrites() {
    root.rewriteQueued = false

    const pending = root.pendingRewrites
    root.pendingRewrites = ({})

    for (const key in pending) {
      const notification = pending[key]
      const name = root.live[key]

      // Archived or dismissed while the rewrite was queued: the entry it belonged
      // to is gone, and a late update must not create a second one.
      if (!name || !notification.tracked) continue

      const stamp = Number(name.slice(0, name.indexOf("-")))
      if (!isFinite(stamp)) continue

      const image = root.imageCopy(name, notification)
      root.enqueue(root.rewriteCommand(name, root.snapshot(notification, stamp, image.path), image))
    }
  }

  // ---- use ----

  // Mirror a notification that has just arrived.
  //
  // Recorded even while silenced: silencing means "do not interrupt me", not
  // "pretend it never happened", and history is exactly where a muted
  // notification is looked for afterwards.
  function begin(notification, discard) {
    if (!notification) return

    // Transient means the protocol does not want it kept beyond its time on
    // screen. Showing it is enough: no live file to restore, no history row.
    if (notification.transient) return

    // Silenced away rather than shown: no live file and no mapping, just a
    // record in history. Written straight there, in one command, because the
    // worker pool would otherwise be free to archive before the write landed.
    if (discard) {
      root.enqueue(root.discardCommand(notification, Date.now()))
      return
    }

    // A notification from before a reload is re-emitted with the same id and
    // `lastGeneration` set. Its file is already on disk and the startup listing
    // maps it; writing a second one would leave the first orphaned and later
    // reaped into history beside it, so the entry would appear twice.
    if (notification.lastGeneration) {
      root.watch(notification)
      return
    }

    const key = String(notification.id)
    const previous = root.live[key]

    // The same object under the same id is a replaces_id update. Keep the file
    // it was first written under — the name carries its timestamp and its place
    // in history — and only rewrite the content.
    if (previous && root.watched[key] === notification) {
      root.queueRewrite(notification)
      return
    }

    // A different object reusing the id is a new notification; ids are reused
    // after the old one is gone. Archive the old entry and give this one its own
    // timestamp rather than letting it inherit the previous card's identity.
    if (previous) {
      delete root.watched[key]
      root.enqueue(root.archiveCommand(previous))
    }

    const stamp = Date.now()
    const name = stamp + "-" + key + ".json"
    const image = root.imageCopy(name, notification)

    root.live[key] = name
    root.watch(notification)
    root.enqueue(root.writeCommand(root.liveDir, name, root.snapshot(notification, stamp, image.path), image))
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
      delete root.watched[id]
      // No handler: this command's output is `ls` and `rm`, not history.
      // Parsing it as JSON would replace the list with nothing every time a
      // notification expired.
      root.enqueue(root.archiveCommand(gone[id]))
    }
  }

  // The callback is optional and runs after `entries` has been replaced. Replay
  // uses it to take a copy of the latest history without the caller having to
  // guess when the asynchronous directory read finished.
  function refresh(handler) {
    // Prune first, then read in the same chain: two workers draining the queue
    // side by side would let the read win the race and briefly show an expired
    // entry.
    root.enqueue(root.pruneHistoryCommand(), function () {
      root.enqueue(root.readCommand(root.historyDir), function (text) {
        root.absorbHistory(text)
        if (handler) handler(root.entries)
      })
    })
  }

  // Only the directory reads collect output. Every other command's stdout is its
  // own noise — file names, `ls`, nothing at all — and handing that to the
  // history parser would throw away a good list.
  function absorbHistory(text) {
    root.entries = root.parse(text)
  }

  // Rebuild the map from the files already on disk, then reap. A line is the
  // filename, a tab, and the one-line JSON body; a torn write simply does not
  // parse and is left for the reaper.
  function absorbLive(text) {
    for (const line of String(text || "").split("\n")) {
      const tab = line.indexOf("\t")
      if (tab <= 0) continue

      try {
        const value = JSON.parse(line.slice(tab + 1))
        if (!value || value.id === undefined) continue

        // A mapping made while the listing was in flight is newer than any file
        // on disk; leave it alone.
        const key = String(value.id)
        if (root.live[key] === undefined) root.live[key] = line.slice(0, tab)
      } catch (e) {
      }
    }

    const keep = []
    for (const id in root.live) keep.push(root.live[id])

    root.ready = true
    root.enqueue(root.reapCommand(keep.join(" ")))
  }

  function clear() {
    root.entries = []
    root.enqueue(root.clearCommand())
  }

  // Actions are deliberately not carried over: they are closures into the
  // sending client's process, which is gone by the time the notification reaches
  // history. A row offering a button that cannot work would be worse than none.
  //
  // `imagePath` is the copy the store made, not the sender's original; it is
  // passed separately because the copy's name depends on the entry's file name.
  function snapshot(notification, stamp, imagePath) {
    const rawSummary = String(notification.summary || "")
    const rawBody = String(notification.body || "")
    const foundCodes = NotificationText.codes(rawSummary + "\n" + rawBody)

    return JSON.stringify({
      id: notification.id,
      app: String(notification.appName || ""),
      // A browser notification is grouped by its site, not by the browser. The
      // resolved source is stored so history rows and replays agree with the
      // live card.
      source: NotificationText.source(notification),
      sourceKey: NotificationText.sourceKey(notification),
      appIcon: String(notification.appIcon || ""),
      summary: NotificationText.redact(rawSummary, foundCodes),
      body: NotificationText.redact(rawBody, foundCodes),
      redacted: foundCodes.length > 0,
      image: String(imagePath === undefined ? (notification.image || "") : imagePath),
      // The glyph and argv a sender attached with `notify`. They are data, not
      // a live action, so unlike the action buttons they still work when the row
      // is replayed from history. The argv is a JSON array, never a shell
      // string: a notification must not be able to turn its text into syntax.
      glyph: root.hint(notification, "anixie-glyph"),
      execArgv: root.hint(notification, "anixie-exec"),
      urgency: notification.urgency,
      timestamp: stamp
    })
  }

  function hint(notification, name) {
    try {
      const hints = notification ? notification.hints : null
      return hints && hints[name] !== undefined ? String(hints[name]) : ""
    } catch (e) {
      return ""
    }
  }
}