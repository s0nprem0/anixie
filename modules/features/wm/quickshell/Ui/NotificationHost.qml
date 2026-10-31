pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "NotificationText.js" as NotificationText

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
//
// The state is split by concern: quiet/persistence, sharing detection, replay
// and click routing each live in their own object, and this file keeps the
// server, the live stack, and the public facade those objects and the rest of
// the shell share.
QtObject {
  id: root

  // Created before anything that may call into them during startup. The quiet
  // state loads a file in its own Component.onCompleted, which can arrive
  // before this object finishes, so the forwards below are guarded.
  property NotificationReplay history: NotificationReplay {
    id: replayState
    host: root
  }

  property NotificationFocus focus: NotificationFocus {}

  property NotificationSharing sharing: NotificationSharing {
    id: sharingState
    host: root
  }

  property NotificationQuiet quietState: NotificationQuiet {
    id: quiet
    host: root
  }

  // ---- silence, snoozes and their preferences ----

  property alias doNotDisturb: quiet.doNotDisturb
  property alias globalSnoozeUntil: quiet.globalSnoozeUntil
  property alias snoozes: quiet.snoozes
  property alias hasSnoozes: quiet.hasSnoozes
  property alias displayMode: quiet.displayMode
  property alias displayName: quiet.displayName
  property alias fullscreenStepAside: quiet.fullscreenStepAside
  property alias historyHours: quiet.historyHours
  property alias codesBypassQuiet: quiet.codesBypassQuiet
  property alias offerSnoozeWhenSharing: quiet.offerSnoozeWhenSharing

  function snoozeOptions() { return quietState.snoozeOptions() }
  function untilTomorrow() { return quietState.untilTomorrow() }
  function snooze(source, seconds) { quietState.snooze(source, seconds) }
  function unsnooze(source) { quietState.unsnooze(source) }
  function quietSources() { return quietState.quietSources() }
  function quietReason(notification) { return quietState.quietReason(notification) }
  function isQuiet(notification) { return quietState.isQuiet(notification) }

  function setDnd(value) { quietState.setDnd(value) }
  function toggle() { quietState.toggle() }
  function setCodesBypass(value) { quietState.setCodesBypass(value) }
  function setDisplayMode(value) { quietState.setDisplayMode(value) }
  function setDisplayName(value) { quietState.setDisplayName(value) }
  function setFullscreenStepAside(value) { quietState.setFullscreenStepAside(value) }
  function setOfferSnoozeWhenSharing(value) { quietState.setOfferSnoozeWhenSharing(value) }
  function setHistoryHours(value) { quietState.setHistoryHours(value) }

  // Called by the quiet state when DND changes while a share is running; kept
  // here because the sharing object may not exist yet when the saved DND file
  // is read during startup.
  function noteSharingSnoozed() {
    if (sharing) sharing.sharingOfferHandled = true
  }

  // ---- screen sharing ----

  property alias sharingActive: sharingState.sharingActive
  property alias sharingStreams: sharingState.sharingStreams
  property alias sharingDetectionAvailable: sharingState.sharingDetectionAvailable
  property alias sharingOfferHandled: sharingState.sharingOfferHandled
  property alias sharingOfferPending: sharingState.sharingOfferPending

  function dismissSharingOffer() { sharing.dismissSharingOffer() }
  function snoozeSharingOffer(seconds) { sharing.snoozeSharingOffer(seconds) }

  // ---- replay and restart grace ----

  property alias replayEntries: replayState.replayEntries
  property alias replaying: replayState.replaying
  property alias restoredEntries: replayState.restoredEntries
  property alias restoring: replayState.restoring

  function restoreLive(entries) { history.restoreLive(entries) }
  function closeRestored() { if (history) history.closeRestored() }
  function restoreFromStore() { if (history) history.restoreFromStore() }
  function replay() { history.replay() }
  function replayEntry(entry) { history.replayEntry(entry) }
  function closeReplay() { if (history) history.closeReplay() }
  function dismissReplay(entry) { history.dismissReplay(entry) }

  Component.onCompleted: {
    if (NotificationStore.ready) root.restoreFromStore()
  }

  // ---- click routing ----

  function activate(notification, link) { focus.activate(notification, link) }
  function focusSource(app, link, source) { focus.focusSource(app, link, source) }

  // ---- the live stack ----

  readonly property var tracked: server.trackedNotifications ? server.trackedNotifications.values : []

  // Newest first, so the popup column reads top-down as most recent.
  readonly property var stacked: {
    const list = []
    for (let i = root.tracked.length - 1; i >= 0; i--) list.push(root.tracked[i])
    return list
  }

  // Notifications from one source, kept together wherever they sit in the stack.
  // A browser is grouped by the site it names, not by the browser process, so a
  // Slack message and a GitHub message do not collapse into "Google-chrome".
  // The popup draws each one as its own card; the grouping only decides the
  // order, so a conversation stays beside itself.
  readonly property var groups: {
    const out = []
    const byApp = Object.create(null)

    for (const item of root.stacked) {
      const key = NotificationText.sourceKey(item)
      const existing = byApp[key]

      if (existing) {
        existing.items.push(item)
        continue
      }

      const next = {
        key: key,
        label: NotificationText.source(item) || key,
        items: [item]
      }
      byApp[key] = next
      out.push(next)
    }

    return out
  }

  // The groups flattened back into one list, in group order. The popup draws
  // these as individual cards rather than collapsing a group to its newest one:
  // a chat that sends three messages should show three cards, not hide two
  // behind a count.
  readonly property var groupedItems: {
    const out = []
    for (const group of root.groups) for (const item of group.items) out.push(item)
    return out
  }

  function dismiss(item) {
    if (item) item.dismiss()
  }

  function dismissAll() {
    for (let i = root.tracked.length - 1; i >= 0; i--) root.tracked[i].dismiss()
    root.closeRestored()
  }

  function dismissOne() {
    const item = root.stacked.length > 0 ? root.stacked[0] : null
    if (!item) return "none"
    item.dismiss()
    return "ok"
  }

  function count() {
    return String(root.tracked.length)
  }

  function hint(notification, name) {
    try {
      const hints = notification ? notification.hints : null
      return hints && hints[name] !== undefined ? String(hints[name]) : ""
    } catch (e) {
      return ""
    }
  }

  function defaultAction(notification) {
    if (!notification || !notification.actions) return null
    for (const action of notification.actions) {
      if (String(action.identifier) === "default") return action
    }
    return null
  }

  function invokeNotification(notification) {
    if (!notification) return "none"

    const exec = root.trustedExec(notification)
    if (exec) {
      Quickshell.execDetached(exec)
      notification.dismiss()
      return "ok"
    }

    const action = root.defaultAction(notification)
    if (action) {
      action.invoke()
      if (!notification.resident) notification.dismiss()
      return "ok"
    }

    const text = String(notification.summary || "") + "\n" + String(notification.body || "")
    root.activate(notification, NotificationText.link(text))
    notification.dismiss()
    return "ok"
  }

  function invokeLast() {
    const item = root.stacked.length > 0 ? root.stacked[0] : null
    return item ? root.invokeNotification(item) : "none"
  }

  function trustedSender(notification) {
    const app = String(notification && (notification.appName || notification.app)
      ? (notification.appName || notification.app)
      : "").toLowerCase()
    return root.quiet.ownApps.indexOf(app) !== -1
  }

  function trustedExec(notification) {
    if (!root.trustedSender(notification)) return null
    return NotificationText.execArgv(root.hint(notification, "anixie-exec"))
  }

  function trustedExecActions(notification) {
    if (!root.trustedSender(notification)) return null
    return NotificationText.execActions(root.hint(notification, "anixie-actions"))
  }

  function sameNotification(a, b) {
    return String(a.appName || "").toLowerCase() === String(b.appName || "").toLowerCase()
      && String(a.summary || "") === String(b.summary || "")
      && String(a.body || "") === String(b.body || "")
  }

  function sweepNow() {
    if (!NotificationStore.ready) return
    if (root.history && root.history.restoring) return

    const ids = []
    for (const notification of root.tracked) ids.push(notification.id)
    NotificationStore.sweep(ids)
  }

  property NotificationServer server: NotificationServer {
    // Editing the bar reloads the shell; that should not wipe what is on
    // screen or lose a notification mid-read.
    keepOnReload: true

    // What the card can actually draw, told to senders. Both default to false:
    // an application that checks the server's capabilities will not send the
    // action buttons the card renders, nor the image it would show. The body is
    // sanitised by NotificationText before it is drawn as rich text, and images
    // beyond the sender's own are still not requested.
    actionsSupported: true
    imageSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true

    onNotification: function (notification) {
      // Silencing means "do not interrupt me", but our own feedback for
      // something the user just did, and a genuine CLI emergency, still show.
      // Everything else is written to history and left untracked, so it never
      // becomes a popup.
      const reason = root.quietReason(notification)
      const quiet = reason !== ""

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

      NotificationStore.begin(notification, quiet, reason)
      if (quiet) return

      const closeKey = notification
      if (root.closeConnected.indexOf(closeKey) < 0) {
        root.closeConnected.push(closeKey)
        notification.closed.connect(function (closeReason) {
          const label = closeReason === 1 ? "expired"
            : closeReason === 2 ? "dismissed"
            : "closed"

          const id = String(notification.id)
          const liveName = root.live[id]
          NotificationStore.noteClose(liveName ? liveName : id, label)

          // Archive the specific entry rather than waiting for a full sweep.
          // This keeps an immediate close from being lost and avoids sweeping
          // the whole store for one notification.
          if (liveName) {
            delete root.live[id]
            delete root.watched[id]
            NotificationStore.enqueue(NotificationStore.archiveCommand(liveName, label))
          }
        })
      }
      notification.tracked = true
    }
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
      if (NotificationStore.ready) root.restoreFromStore()
    }
  }
}
