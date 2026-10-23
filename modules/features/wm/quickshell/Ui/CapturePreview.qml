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
  property bool shown: false
  property bool pinned: false

  // Incremented whenever the same path is revealed again — after it was
  // annotated in place, for instance. The card puts it in the image URL so Qt
  // does not keep showing the old pixels for an unchanged file name.
  property int revision: 0

  // Ten seconds, as the reference gives it.
  readonly property int previewMs: 10000

  function reveal(nextPath) {
    if (!nextPath) return

    root.path = String(nextPath)
    root.revision += 1
    root.shown = true

    // Pinning means "this stays on screen", not "this exact file stays". A
    // capture taken while one is pinned replaces it, and the new one inherits
    // the pin rather than being dismissed ten seconds later — or the old one
    // vanishing without the pin ever being released.
    if (root.pinned) hideTimer.stop()
    else hideTimer.restart()
  }

  // Pinning is what stops the timer. The window stays up until it is dismissed,
  // which is the point: the capture is on screen to be looked at or compared
  // against, and ten seconds is not enough for either.
  function togglePin() {
    root.pinned = !root.pinned
    if (root.pinned) hideTimer.stop()
    else hideTimer.restart()
  }

  function hide() {
    root.shown = false
    root.pinned = false
    root.path = ""
    hideTimer.stop()
  }

  // Declared as a property value rather than as a child: QtObject has no default
  // property, so a bare `Timer { }` inside it has nowhere to go. This is the same
  // shape OsdHost uses for its own timers.
  property Timer hideTimer: Timer {
    interval: root.previewMs
    repeat: false
    onTriggered: root.hide()
  }
}
