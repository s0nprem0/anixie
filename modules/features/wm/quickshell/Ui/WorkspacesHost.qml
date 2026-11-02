pragma Singleton

import QtQuick

// The workspace widgets, one per bar, behind a single IPC target.
//
// The layout cycle belongs to a widget because that is where the per-monitor
// workspace and its layout are read. Registering an IpcHandler inside the
// widget would register one per bar, and only one of those can win: with two
// displays, `workspaces cycle` could act on the bar that is not focused. The
// handler lives in shell.qml instead and asks this for the focused copy.
QtObject {
  id: root

  // Widgets in load order. The display is resolved when one is looked up, not
  // when it registers: at Component.onCompleted a bar has not been shown yet,
  // so its attached Screen is unset and every copy would look the same.
  property var items: []

  function register(item) {
    if (!item) return

    const next = []
    for (let i = 0; i < root.items.length; i++) {
      if (root.items[i] !== item) next.push(root.items[i])
    }
    next.push(item)
    root.items = next
  }

  function unregister(item) {
    if (!item) return

    const next = []
    let removed = false
    for (let i = 0; i < root.items.length; i++) {
      if (root.items[i] === item) {
        removed = true
        continue
      }
      next.push(root.items[i])
    }
    if (removed) root.items = next
  }

  // The widget on the focused output, or the newest copy while screens are
  // still coming up.
  function focused() {
    const name = Screens.focusedName
    if (name !== "") {
      for (let i = root.items.length - 1; i >= 0; i--) {
        if (Screens.screenNameOf(root.items[i]) === name) return root.items[i]
      }
    }
    return root.items.length > 0 ? root.items[root.items.length - 1] : null
  }

  function cycle() {
    const item = root.focused()
    if (item) item.cycleLayout()
  }

  function refresh() {
    const item = root.focused()
    if (item) item.refreshLayout()
  }
}
