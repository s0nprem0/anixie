pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification daemon. The shell owns org.freedesktop.Notifications
// itself, so there is no second process to keep in step with it — the same
// arrangement the reference uses.
//
// A notification is tracked while it is on screen, which is what puts it in
// `trackedNotifications` for the popups to draw and for anything to dismiss.
// One arriving while silencing is on is left untracked, so it is dropped as a
// popup — but it is still written to history, since silencing means "do not
// interrupt me", not "pretend it never happened".
//
// NotificationStore mirrors each notification to disk for as long as it is
// here, and archives the file once it goes, which is what gives the shell a
// history it did not have before.
QtObject {
  id: root

  property bool doNotDisturb: false

  // Silencing survives a shell restart. A restart is invisible to the user —
  // updates perform one — and coming back unsilenced turns the next batch of
  // messages into popups the user had explicitly asked not to see.
  readonly property string dndPath: NotificationStore.stateDir + "/dnd"

  // Guards the write that hydrating the saved value would otherwise trigger.
  property bool _hydrating: false
  property string _pendingDnd: ""

  function loadDnd() {
    let text = ""
    try {
      text = String(root.dndFile.text()).trim()
    } catch (e) {
      // No file yet: the first run starts unsilenced.
    }
    if (text === "") return

    root._hydrating = true
    root.doNotDisturb = text === "on" || text === "true" || text === "1"
    root._hydrating = false
  }

  // Written through a process and a file adapter, the same way the bar's layout
  // is saved: the directory is made first, because a write into a directory that
  // does not exist yet is a drop that silently does nothing.
  function saveDnd() {
    root._pendingDnd = root.doNotDisturb ? "on\n" : "off\n"
    root.dndMkdir.running = false
    root.dndMkdir.running = true
  }

  property FileView dndFile: FileView {
    path: Qt.resolvedUrl(root.dndPath)
    printErrors: false
    blockLoading: true
    atomicWrites: true

    Component.onCompleted: root.loadDnd()
  }

  property Process dndMkdir: Process {
    command: ["mkdir", "-p", NotificationStore.stateDir]
    running: false

    onExited: {
      if (root._pendingDnd === "") return
      root.dndFile.setText(root._pendingDnd)
      root._pendingDnd = ""
    }
  }

  // Which senders are allowed through silencing. Critical urgency by itself is
  // not a reason: chat applications mark everything critical to force their way
  // in front of the user. Trusted are our own confirmations for something the
  // user just did — reminders, a screenshot, a recording, an output switch — and
  // bare-CLI emergencies, which are almost always a system script rather than a
  // brand.
  readonly property var ownApps: [
    "audio", "battery", "capture", "nixos", "record", "reminders", "sessions"
  ]

  function bypassesSilencing(notification) {
    const app = String(notification.appName || "").toLowerCase()

    if (root.ownApps.indexOf(app) !== -1) return true
    return app === "notify-send" && notification.urgency === NotificationUrgency.Critical
  }

  // Replayed history is deliberately separate from `tracked`: those
  // notifications are gone, their senders' actions are dead, and they must not
  // be swept into history a second time. The popup window draws either the live
  // stack or this replay, never both.
  property var replayEntries: []
  property bool replaying: false

  readonly property var tracked: server.trackedNotifications ? server.trackedNotifications.values : []

  // Newest first, so the popup column reads top-down as most recent.
  readonly property var stacked: {
    const list = []
    for (let i = root.tracked.length - 1; i >= 0; i--) list.push(root.tracked[i])
    return list
  }

  // Notifications from one application, collapsed into one card wherever they
  // sit in the stack. A chat that sends five messages should take one card and
  // a number, not five cards that push everything else off the screen — and a
  // second message from an app already on screen belongs with the first, not in
  // a separate card below whatever arrived in between.
  readonly property var groups: {
    const out = []
    const byApp = ({})

    for (const item of root.stacked) {
      const app = String(item.appName || "").toLowerCase()
      const existing = byApp[app]

      if (existing) {
        existing.items.push(item)
        continue
      }

      const next = { app: app, items: [item] }
      byApp[app] = next
      out.push(next)
    }

    return out
  }

  function dismiss(item) {
    if (item) item.dismiss()
  }

  function dismissAll() {
    for (let i = root.tracked.length - 1; i >= 0; i--) root.tracked[i].dismiss()
  }

  // What silencing may take with it: everything except the messages that are
  // allowed through it. Turning DND on must not throw away the critical alert
  // that was meant to survive it.
  function dismissSilenced() {
    for (let i = root.tracked.length - 1; i >= 0; i--) {
      const item = root.tracked[i]
      if (!root.bypassesSilencing(item)) item.dismiss()
    }
  }

  function sameNotification(a, b) {
    return String(a.appName || "").toLowerCase() === String(b.appName || "").toLowerCase()
      && String(a.summary || "") === String(b.summary || "")
      && String(a.body || "") === String(b.body || "")
  }

  // Show the newest history entries for a few seconds. `NotificationStore` reads
  // from disk asynchronously, so the popup is only made visible once there is
  // something to draw.
  function replay() {
    NotificationStore.refresh(function (entries) {
      root.replayEntries = entries.slice(0, 10)
      root.replaying = root.replayEntries.length > 0
      if (root.replaying) root.replayTimer.restart()
    })
  }

  function closeReplay() {
    root.replayTimer.stop()
    root.replayEntries = []
    root.replaying = false
  }

  function dismissReplay(entry) {
    const next = []
    for (const item of root.replayEntries) if (item !== entry) next.push(item)
    root.replayEntries = next
    if (next.length === 0) root.closeReplay()
  }

  property Timer replayTimer: Timer {
    interval: 12000
    onTriggered: root.closeReplay()
  }

  function toggle() {
    root.doNotDisturb = !root.doNotDisturb
  }

  // Silencing takes the current batch with it, so the screen matches the state
  // the indicator is showing — and a replay, being a temporary view of the past,
  // should not linger over the desktop.
  onDoNotDisturbChanged: {
    if (root._hydrating) return

    root.saveDnd()

    if (root.doNotDisturb) {
      root.closeReplay()
      root.dismissSilenced()
    }
  }

  property NotificationServer server: NotificationServer {
    // Editing the bar reloads the shell; that should not wipe what is on
    // screen or lose a notification mid-read.
    keepOnReload: true

    // What the card can actually draw, told to senders. Both default to false:
    // an application that checks the server's capabilities will not send the
    // action buttons the card renders, nor the image it would show. Markup is
    // left off because the body is drawn as plain text.
    actionsSupported: true
    imageSupported: true

    onNotification: function (notification) {
      // Silencing means "do not interrupt me", but our own feedback for
      // something the user just did, and a genuine CLI emergency, still show.
      // Everything else is written to history and left untracked, so it never
      // becomes a popup.
      const quiet = root.doNotDisturb && !root.bypassesSilencing(notification)

      // An app repeating itself — a polling script, a volume readout — is one
      // piece of information. Keep the newest card instead of stacking an
      // identical one under it; the older entry is archived as it is dismissed.
      // The same object is skipped: that is an in-place update, not a repeat.
      if (!quiet) {
        for (let i = root.tracked.length - 1; i >= 0; i--) {
          const existing = root.tracked[i]
          if (existing === notification) break
          if (root.sameNotification(existing, notification)) {
            existing.dismiss()
            break
          }
        }
      }

      NotificationStore.begin(notification, quiet)
      if (quiet) return

      notification.tracked = true
    }
  }

  function sweepNow() {
    const ids = []
    for (const notification of root.tracked) ids.push(notification.id)
    NotificationStore.sweep(ids)
  }

  // Nothing calls us when a notification ends: the card expires or dismisses it,
  // but the client is equally free to close its own notification, and that never
  // reaches the shell. The tracked list is what drops the entry when that
  // happens, so watching the list archives the moment it does — every insert
  // and removal, rather than polling for a gap once a second.
  //
  // Held as properties rather than declared as children: a QtObject has no
  // default property, so a bare `Connections { }` here has nowhere to go.
  property Connections trackedChanges: Connections {
    target: root.server.trackedNotifications
    function onValuesChanged() { root.sweepNow() }
  }

  // One reconciliation after startup, not a poll: the store builds its
  // id-to-file map off disk asynchronously, and after a reload the daemon
  // re-emits what it still holds. Waiting for `ready` means that read is done,
  // so anything still in `live` that is not tracked is a popup the shell did
  // not survive, and is archived now rather than left for the reaper.
  property Connections storeReady: Connections {
    target: NotificationStore
    function onReadyChanged() {
      if (NotificationStore.ready) root.sweepNow()
    }
  }
}
