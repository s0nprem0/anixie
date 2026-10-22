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

  // name -> screenName -> { anchor, builder }
  property var entries: ({})

  function register(name, anchor, builder) {
    if (!name || !anchor || !builder) return

    const screenName = Screens.nameOf(anchor)

    const byScreen = {}
    const previous = root.entries[name] || ({})
    for (const key in previous) byScreen[key] = previous[key]
    byScreen[screenName] = { anchor: anchor, builder: builder }

    const next = {}
    for (const key in root.entries) next[key] = root.entries[key]
    next[name] = byScreen
    root.entries = next

    // Screens can be unplugged. A QML item cannot be observed from outside its
    // component, so the entries for a display that has gone are pruned when the
    // set of screens changes rather than when the bar is destroyed.
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
      const byScreen = root.entries[name]
      const kept = {}
      for (const screenName in byScreen) {
        if (connected[screenName]) kept[screenName] = byScreen[screenName]
        else changed = true
      }
      if (Object.keys(kept).length > 0) next[name] = kept
    }

    if (changed) root.entries = next
  }

  function unregister(name, anchor, screenName) {
    const byScreen = root.entries[name]
    if (!byScreen) return

    const entry = byScreen[screenName]
    if (!entry || entry.anchor !== anchor) return

    const remaining = {}
    for (const key in byScreen) if (key !== screenName) remaining[key] = byScreen[key]

    const next = {}
    for (const key in root.entries) next[key] = root.entries[key]
    if (Object.keys(remaining).length > 0) next[name] = remaining
    else delete next[name]
    root.entries = next
  }

  function entryFor(name, anchor) {
    const byScreen = root.entries[name]
    if (!byScreen) return null

    const wanted = anchor ? Screens.nameOf(anchor) : Screens.focusedName
    return byScreen[wanted]
      || byScreen[Screens.focusedName]
      || byScreen[Object.keys(byScreen)[0]]
      || null
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
      if (Screens.nameOf(entry.anchor) !== Screens.nameOf(host)) continue
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
