import QtQuick
import Quickshell
import Quickshell.Io

// Replay and restart grace. The daemon's live stack is the source of truth;
// this keeps the two temporary views that sit beside it: the last ten history
// cards and the notifications that were on screen when the shell stopped.
QtObject {
  id: history

  property var host: null

  // Replayed history is deliberately separate from `tracked`: those
  // notifications are gone, their senders' actions are dead, and they must not
  // be swept into history a second time. The popup window draws either the live
  // stack or this replay, never both.
  property var replayEntries: []
  property bool replaying: false

  // Notifications that were on screen when the previous shell stopped. They are
  // history snapshots, but they get a short grace in the live deck so a restart
  // — which an update performs — does not silently swallow them.
  property var restoredEntries: []
  property bool restoring: false

  property Timer restoreTimer: Timer {
    interval: 20000
    onTriggered: history.closeRestored()
  }

  function restoreLive(entries) {
    if (!entries || entries.length === 0) return
    history.restoredEntries = entries.slice().sort(function (a, b) {
      return Number(b.timestamp || 0) - Number(a.timestamp || 0)
    }).slice(0, 10)
    history.restoring = history.restoredEntries.length > 0
    if (history.restoring) history.restoreTimer.restart()
  }

  function closeRestored() {
    history.restoreTimer.stop()
    history.restoredEntries = []
    history.restoring = false
  }

  function restoreFromStore() {
    if (!NotificationStore.ready) return

    // A config reload re-emits the notifications the server still holds; those
    // are already live and must not be duplicated from disk. A full restart has
    // none tracked, so every live file is a card to put back for a moment.
    const liveIds = {}
    for (const notification of history.host.tracked) liveIds[String(notification.id)] = true
    const restored = NotificationStore.takeLive().filter(function (entry) {
      return liveIds[String(entry.id)] !== true
    })
    history.restoreLive(restored)
    history.host.sweepNow()
  }


  // Show the newest history entries for a few seconds. `NotificationStore` reads
  // from disk asynchronously, so the popup is only made visible once there is
  // something to draw.
  function replay() {
    history.closeRestored()
    NotificationStore.refresh(function (entries) {
      // Held notifications were never shown; replaying them as if they had been
      // would be a different action from replaying closed history.
      const shown = entries.filter(function (entry) { return entry.quiet !== true })
      history.replayEntries = shown.slice(0, 10)
      history.replaying = history.replayEntries.length > 0
      if (history.replaying) history.replayTimer.restart()
    })
  }

  // A held row in the panel. It is still a history snapshot, so it opens as a
  // replay card rather than as a live notification with actions that no longer
  // exist.
  function replayEntry(entry) {
    if (!entry) return
    history.closeRestored()
    history.replayEntries = [entry]
    history.replaying = true
    history.replayTimer.restart()
  }

  function closeReplay() {
    history.replayTimer.stop()
    history.replayEntries = []
    history.replaying = false
  }

  function dismissReplay(entry) {
    if (history.restoring) {
      const restored = []
      for (const item of history.restoredEntries) if (item !== entry) restored.push(item)
      history.restoredEntries = restored
      if (restored.length === 0) history.closeRestored()
      return
    }

    const next = []
    for (const item of history.replayEntries) if (item !== entry) next.push(item)
    history.replayEntries = next
    if (next.length === 0) history.closeReplay()
  }

  property Timer replayTimer: Timer {
    interval: 12000
    onTriggered: history.closeReplay()
  }
}
