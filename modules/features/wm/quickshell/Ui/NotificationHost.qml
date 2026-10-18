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

  readonly property var tracked: server.trackedNotifications ? server.trackedNotifications.values : []

  // Newest first, so the popup column reads top-down as most recent.
  readonly property var stacked: {
    const list = []
    for (let i = root.tracked.length - 1; i >= 0; i--) list.push(root.tracked[i])
    return list
  }

  function dismiss(item) {
    if (item) item.dismiss()
  }

  function dismissAll() {
    for (let i = root.tracked.length - 1; i >= 0; i--) root.tracked[i].dismiss()
  }

  function toggle() {
    root.doNotDisturb = !root.doNotDisturb
  }

  // Silencing takes the current batch with it, so the screen matches the state
  // the indicator is showing.
  onDoNotDisturbChanged: if (root.doNotDisturb) root.dismissAll()

  property NotificationServer server: NotificationServer {
    // Editing the bar reloads the shell; that should not wipe what is on
    // screen or lose a notification mid-read.
    keepOnReload: true

    onNotification: function (notification) {
      NotificationStore.begin(notification)
      if (root.doNotDisturb) return
      notification.tracked = true
    }
  }

  // Nothing calls us when a notification ends: the card expires or dismisses it,
  // but the client is equally free to close its own notification, and that never
  // reaches the shell at all. So the tracked list is polled and whatever has
  // dropped out of it is archived. A second is far finer than a human can notice
  // in the gap between a toast going and its entry appearing in the panel.
  //
  // Held as a property rather than declared as a child: a QtObject has no
  // default property, so a bare `Timer { }` here has nowhere to go.
  property Timer sweeper: Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const ids = []
      for (const notification of root.tracked) ids.push(notification.id)
      NotificationStore.sweep(ids)
    }
  }
}
