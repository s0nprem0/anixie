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
//
// There is now one bar per screen, so the same widget registers once per screen.
// A click passes its own anchor and opens on that anchor's display; a hotkey has
// no anchor, so it uses the focused display's copy. That is also what makes the
// numbered hotkeys follow the bar you are actually looking at.
QtObject {
  id: root

  // name -> [{ anchor, builder }], one copy per bar that carries the widget.
  //
  // The display is intentionally not part of the key. A widget registers from
  // Component.onCompleted, before its bar has been shown, so its attached Screen
  // is still unset. Resolving it then collapsed every copy onto the focused
  // output: with an external monitor connected, both bars registered under it
  // and every panel opened there — even one clicked on the laptop's own bar.
  // The screen is resolved when the panel is opened instead.
  property var entries: ({})

  function copies(name) {
    return root.entries[name] || []
  }

  function screenOf(entry) {
    return entry && entry.anchor ? Screens.screenNameOf(entry.anchor) : ""
  }

  function register(name, anchor, builder) {
    if (!name || !anchor || !builder) return

    const previous = root.copies(name)
    const kept = []
    let replaced = false
    for (let i = 0; i < previous.length; i++) {
      if (previous[i].anchor !== anchor) {
        kept.push(previous[i])
        continue
      }
      kept.push({ anchor: anchor, builder: builder })
      replaced = true
    }
    if (!replaced) kept.push({ anchor: anchor, builder: builder })

    const next = {}
    for (const key in root.entries) next[key] = root.entries[key]
    next[name] = kept
    root.entries = next

    // Screens can be unplugged while the shell runs. A QML item cannot be
    // observed from outside its component, so stale copies are pruned when the
    // set of screens changes and whenever another copy registers.
    root.prune()
  }

  // The names of the connected screens, as one value. Reading the list itself
  // would not tell a binding when a monitor was swapped for another.
  readonly property string screenNames: Screens.names

  onScreenNamesChanged: root.prune()

  function prune() {
    const connected = {}
    for (let i = 0; i < Screens.all.length; i++) connected[String(Screens.all[i].name)] = true

    let changed = false
    const next = {}
    for (const name in root.entries) {
      const previous = root.entries[name]
      const kept = []
      for (let i = 0; i < previous.length; i++) {
        const entry = previous[i]
        const screenName = root.screenOf(entry)
        // Keep a copy whose bar has not been shown yet: it is the one being
        // built right now. Drop a destroyed anchor, or one whose output is no
        // longer connected.
        if (!entry.anchor || (screenName !== "" && !connected[screenName])) {
          changed = true
          continue
        }
        kept.push(entry)
      }
      if (kept.length > 0) next[name] = kept
      else if (previous.length > 0) changed = true
    }

    if (changed) root.entries = next
  }

  function unregister(name, anchor) {
    const previous = root.copies(name)
    if (previous.length === 0) return

    const kept = []
    let removed = false
    for (let i = 0; i < previous.length; i++) {
      if (previous[i].anchor === anchor) {
        removed = true
        continue
      }
      kept.push(previous[i])
    }
    if (!removed) return

    const next = {}
    for (const key in root.entries) next[key] = root.entries[key]
    if (kept.length > 0) next[name] = kept
    else delete next[name]
    root.entries = next
  }

  function entryFor(name, anchor) {
    const previous = root.copies(name)
    if (previous.length === 0) return null

    // A click names its own copy exactly, which is what keeps it on the bar it
    // came from.
    if (anchor) {
      for (let i = previous.length - 1; i >= 0; i--) {
        if (previous[i].anchor === anchor) return previous[i]
      }
    }

    // A hotkey has no anchor, so it takes the focused display's copy. The
    // newest match wins, so a bar rebuilt after a hotplug beats the stale copy
    // it replaced.
    const wanted = anchor ? Screens.screenNameOf(anchor) : Screens.focusedName
    if (wanted) {
      for (let i = previous.length - 1; i >= 0; i--) {
        if (root.screenOf(previous[i]) === wanted) return previous[i]
      }
    }

    return previous[previous.length - 1]
  }

  function toggle(name, anchor) {
    const entry = root.entryFor(name, anchor)
    if (!entry || !entry.anchor) {
      console.warn("quickshell panels: nothing is registered as \"" + name + "\"")
      return
    }

    PanelHost.toggle(name, entry.anchor, entry.builder)
  }

  // Panels left to right (or top to bottom on a side bar), by where their
  // buttons are on the focused screen's bar rather than by the order the widgets
  // happened to register. This is what the numbered hotkeys count, so the number
  // matches the icon you would point at — the same promise Omarchy's
  // `Super+Ctrl+1-9` makes.
  function ordered() {
    const list = []
    const host = PanelHost.focusedBar
    if (!host) return []

    for (const name in root.entries) {
      const entry = root.entryFor(name, null)
      if (!entry || !entry.anchor) continue
      const entryScreen = root.screenOf(entry) || Screens.focusedName
      const hostScreen = Screens.screenNameOf(host) || Screens.focusedName
      if (entryScreen !== hostScreen) continue
      const point = entry.anchor.mapToItem(host, 0, 0)
      list.push({ name: name, x: point.x, y: point.y })
    }

    list.sort(function (a, b) {
      return PanelHost.vertical ? a.y - b.y : a.x - b.x
    })
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
