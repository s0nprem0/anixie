pragma Singleton

import QtQuick

// The screenshot preview: the capture, shown for ten seconds after it is taken,
// with a way to keep it on screen.
//
// State lives here and the window that draws it lives in shell.qml, the same
// split the on-screen display uses. `shot` reaches this through the shell's IPC
// rather than drawing anything itself, so the preview works the same whether the
// capture came from a key, from the capture menu, or from a shell.
QtObject {
  id: root

  property string path: ""
  property string screenName: ""
  property bool shown: false
  property bool pinned: false

  // Whether the copy that `shot` makes before revealing this capture failed.
  // It rides alongside the path rather than being a property of the card,
  // because the failure happens in the shell script, before the card exists.
  // The card shows it and clears it when a retry from the card succeeds.
  property bool copyFailed: false

  // Incremented whenever the same path is revealed again — after it was
  // annotated in place, for instance. The card puts it in the image URL so Qt
  // does not keep showing the old pixels for an unchanged file name.
  property int revision: 0

  // Ten seconds, as the reference gives it.
  readonly property int previewMs: 10000

  function isValidPath(nextPath) {
    if (nextPath === undefined || nextPath === null) return false
    if (typeof nextPath === "object") return false
    const p = String(nextPath)
    if (p.trim() === "") return false
    return true
  }

  function reveal(nextPath) {
    if (!root.isValidPath(nextPath)) return

    const p = String(nextPath)
    root.path = p
    root.copyFailed = false
    root.screenName = Screens.focused ? Screens.focused.name : ""
    root.revision = (root.revision + 1) >>> 0 // avoid overflow issues
    root.shown = true

    // Pinning means "this stays on screen", not "this exact file stays". A
    // capture taken while one is pinned replaces it, and the new one inherits
    // the pin rather than being dismissed ten seconds later — or the old one
    // vanishing without the pin ever being released.
    if (root.pinned) {
      hideTimer.stop()
    } else {
      hideTimer.restart()
    }
  }

  // Pinning is what stops the timer. The window stays up until it is dismissed,
  // which is the point: the capture is on screen to be looked at or compared
  // against, and ten seconds is not enough for either.
  function togglePin() {
    if (!root.shown || root.path === "") {
      return
    }
    root.pinned = !root.pinned
    if (root.pinned) {
      hideTimer.stop()
    } else {
      hideTimer.restart()
    }
  }

  // `shot` knows whether the automatic copy worked, and the card cannot: by the
  // time the image is on screen the shell script has already exited. This is the
  // entry point for the case where it did not, so the card can say "not copied"
  // instead of letting the user paste stale clipboard contents and wonder.
  function revealCopyFailed(nextPath) {
    root.reveal(nextPath)
    if (!root.shown) return
    root.copyFailed = true
  }

  function noteCopyFailure() {
    if (!root.shown) return
    root.copyFailed = true
  }

  function clearCopyFailure() {
    root.copyFailed = false
  }

  // Hovering the card holds it open. Ten seconds is enough to glance at a
  // capture and not enough to read one, and vanishing under the pointer while it
  // is being looked at is the worst possible moment. Leaving restarts the full
  // interval rather than resuming a countdown: the card has no visible timer, and
  // a resume would vanish mid-sentence with no warning.
  function pause() {
    if (!root.shown || root.pinned) return
    hideTimer.stop()
  }

  function resume() {
    if (!root.shown || root.pinned) return
    hideTimer.restart()
  }

  // What the IPC status call answers, so a script — or a person debugging with
  // `quickshell ipc call capture status` — can tell whether a card is up and
  // whether it is staying.
  function status() {
    if (!root.shown) return "closed"
    return root.pinned ? "open pinned" : "open"
  }

  function hide() {
    root.shown = false
    root.pinned = false
    root.path = ""
    root.screenName = ""
    root.copyFailed = false
    hideTimer.stop()
  }

  // Declared as a property value rather than as a child: QtObject has no default
  // property, so a bare `Timer { }` inside it has nowhere to go. This is the same
  // shape OsdHost uses for its own timers.
  property Timer hideTimer: Timer {
    interval: root.previewMs
    repeat: false
    onTriggered: {
      // Only auto-hide if still visible and not pinned
      if (root.shown && !root.pinned && root.path !== "") {
        root.hide()
      } else if (root.shown && root.pinned) {
        // Should not happen if pinned, but ensure timer stopped
        hideTimer.stop()
      } else {
        hideTimer.stop()
      }
    }
  }
}
