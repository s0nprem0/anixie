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

    PanelHost.toggle(entry.anchor, entry.builder)
  }

  function names() {
    return Object.keys(root.entries).sort()
  }
}
