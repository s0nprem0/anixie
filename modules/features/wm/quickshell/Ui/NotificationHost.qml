pragma Singleton

import QtQuick
import Quickshell
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

  // Consecutive notifications from one application, collapsed into one card.
  // A chat that sends five messages should take one card and a number, not five
  // cards that push everything else off the screen. Only consecutive ones: two
  // messages from one app either side of one from another are two moments, not
  // one.
  readonly property var groups: {
    const out = []
    for (const item of root.stacked) {
      const app = String(item.appName || "").toLowerCase()
      const last = out.length > 0 ? out[out.length - 1] : null
      if (last && last.app === app) {
        last.items.push(item)
        continue
      }
      out.push({ app: app, items: [item] })
    }
    return out
  }

  function dismiss(item) {
    if (item) item.dismiss()
  }

  function dismissAll() {
    for (let i = root.tracked.length - 1; i >= 0; i--) root.tracked[i].dismiss()
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
  onDoNotDisturbChanged: if (root.doNotDisturb) {
    root.closeReplay()
    root.dismissAll()
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
      // Silencing means "do not interrupt me", and a critical notification — a
      // failing battery, an alarm — is the one thing that has earned the
      // interruption. Everything else is written to history and left untracked,
      // so it never becomes a popup.
      const quiet = root.doNotDisturb && notification.urgency !== NotificationUrgency.Critical
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
