pragma Singleton

import QtQuick
import ".."

// Panels, reachable by name.
//
// A panel opens against the button it belongs to — that is what places it under
// the right glyph, and it is the whole reason the hotkey is worth having rather
// than aiming at a 16-pixel target. So the hotkey needs the same two things the
// click has: the widget's anchor item and the component that builds the panel.
//
// Neither is reachable from shell.qml, where the IPC handler lives. Each widget
// therefore registers its pair here when it loads, and the handler looks it up.
// Registration is by name rather than by reference so the keys stay readable and
// a panel that is not on the bar fails with a message instead of silently doing
// nothing.
QtObject {
  id: root

  // name -> { anchor, builder }
  property var entries: ({})

  function register(name, anchor, builder) {
    if (!name || !anchor || !builder) return
    root.entries[name] = { anchor: anchor, builder: builder }
  }

  function toggle(name) {
    const entry = root.entries[name]
    if (!entry) {
      console.warn("quickshell panels: nothing is registered as \"" + name + "\"")
      return
    }

    PanelHost.toggle(name, entry.anchor, entry.builder)
  }

  // Panels left to right, by where their buttons are on the bar rather than by
  // the order the widgets happened to register. This is what the numbered hotkeys
  // count, so the number matches the icon you would point at — the same promise
  // Omarchy's `Super+Ctrl+1-9` makes.
  function ordered() {
    const list = []

    for (const name in root.entries) {
      const entry = root.entries[name]
      if (!entry || !entry.anchor || !PanelHost.host) continue
      list.push({ name: name, x: entry.anchor.mapToItem(PanelHost.host, 0, 0).x })
    }

    list.sort(function (a, b) { return a.x - b.x })
    return list.map(function (entry) { return entry.name })
  }

  // One-based, as the key that calls it is: `panel position 3` is the third
  // panel from the left.
  function togglePosition(position) {
    const names = root.ordered()
    const index = parseInt(position, 10) - 1
    if (!(index >= 0 && index < names.length)) return

    root.toggle(names[index])
  }

  function names() {
    return Object.keys(root.entries).sort()
  }
}
