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
    if (typeof name !== "string" || name === "") return []
    return root.entries[name] || []
  }

  function isAlive(item) {
    if (!item) return false
    try {
      const value = item.parent
      return true
    } catch (e) {
      return false
    }
  }

  function isValid(entry) {
    if (!entry || !entry.anchor || !entry.builder) return false
    if (!root.isAlive(entry.anchor)) return false
    return true
  }

  function screenOf(entry) {
    if (!root.isValid(entry)) return ""
    try {
      return String(Screens.screenNameOf(entry.anchor) || "")
    } catch (e) {
      return ""
    }
  }

  function register(name, anchor, builder) {
    if (typeof name !== "string" || name === "") return
    if (!anchor || !builder) return
    if (!root.isAlive(anchor)) return

    const previous = root.copies(name)
    const kept = []
    for (let i = 0; i < previous.length; i++) {
      if (previous[i].anchor !== anchor) kept.push(previous[i])
    }
    kept.push({ anchor: anchor, builder: builder })

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
    const all = Screens.all || []
    const connected = {}
    for (let i = 0; i < all.length; i++) {
      try {
        connected[String(all[i].name)] = true
      } catch (e) {
      }
    }

    let changed = false
    const next = {}
    for (const name in root.entries) {
      const previous = root.entries[name] || []
      const kept = []
      for (let i = 0; i < previous.length; i++) {
        const entry = previous[i]
        if (!root.isValid(entry)) {
          changed = true
          continue
        }

        const screenName = root.screenOf(entry)
        // Keep a copy whose bar has not been shown yet: it is the one being
        // built right now. Drop a destroyed anchor, or one whose output is no
        // longer connected.
        if (screenName !== "" && !connected[screenName]) {
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
    if (typeof name !== "string" || name === "") return
    if (!anchor) return

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
    // came from. An explicit but unregistered anchor must not fall through to
    // another widget instance.
    if (anchor) {
      for (let i = previous.length - 1; i >= 0; i--) {
        if (previous[i].anchor === anchor) return previous[i]
      }
      return null
    }

    // A hotkey has no anchor, so it takes the focused display's copy. The
    // newest valid match wins, so a bar rebuilt after a hotplug beats the stale
    // copy it replaced. There is intentionally no fallback to an unrelated
    // monitor.
    const wanted = Screens.focusedName
    if (wanted) {
      for (let i = previous.length - 1; i >= 0; i--) {
        const entry = previous[i]
        if (!root.isValid(entry)) continue
        if (root.screenOf(entry) === wanted) return entry
      }
    }

    return null
  }

  // The item a panel should hang off. Usually the widget's own button, but a
  // widget parked in the tray lives in the drawer's window, which hides as soon
  // as its panel opens. Use the tray handle on the bar instead: it is the part
  // that stays put, and it keeps the panel on screen instead of anchoring it to
  // a window that is no longer mapped.
  function displayAnchor(entry) {
    const anchor = entry ? entry.anchor : null
    if (!anchor || !root.isAlive(anchor)) return anchor

    const screenName = root.screenOf(entry)
    let host = null
    if (screenName !== "") {
      try {
        host = PanelHost.barFor(screenName)
      } catch (e) {
        host = null
      }
    }

    if (!host) return anchor

    let anchorWindow = null
    let hostWindow = null
    try {
      anchorWindow = anchor.Window && anchor.Window.window ? anchor.Window.window : null
    } catch (e) {
      anchorWindow = null
    }
    try {
      hostWindow = host.Window && host.Window.window ? host.Window.window : null
    } catch (e) {
      hostWindow = null
    }

    if (anchorWindow && hostWindow && anchorWindow === hostWindow) return anchor

    const trays = BarContext.trays || []
    for (let i = 0; i < trays.length; i++) {
      const tray = trays[i]
      if (tray && tray.screenName === screenName && tray.handle && root.isAlive(tray.handle)) {
        return tray.handle
      }
    }

    return anchor
  }

  function toggle(name, anchor) {
    const entry = root.entryFor(name, anchor)
    if (!entry || !entry.anchor || !root.isAlive(entry.anchor) || !entry.builder) {
      console.warn("quickshell panels: nothing is registered as \"" + name + "\"")
      return
    }

    const display = root.displayAnchor(entry)
    if (!display || !root.isAlive(display)) {
      console.warn("quickshell panels: no display anchor for \"" + name + "\"")
      return
    }

    PanelHost.toggle(name, display, entry.builder)
  }

  // Panels left to right (or top to bottom on a side bar), by where their
  // buttons are on the focused screen's bar rather than by the order the widgets
  // happened to register. This is what the numbered hotkeys count, so the number
  // matches the icon you would point at — the same promise Omarchy's
  // `Super+Ctrl+1-9` makes.
  //
  // Tray widgets are grouped after ordinary bar widgets: their own anchors live in
  // the drawer window, so they cannot be ordered by bar coordinates. They use
  // the tray handle as a stable anchor and are then ordered deterministically by
  // name.
  function ordered() {
    const host = PanelHost.focusedBar
    if (!host) return []

    let hostScreen = ""
    try {
      hostScreen = Screens.screenNameOf(host) || ""
    } catch (e) {
      hostScreen = ""
    }
    if (hostScreen === "") hostScreen = Screens.focusedName

    const vertical = !!PanelHost.vertical
    const list = []

    for (const name in root.entries) {
      const entry = root.entryFor(name, null)
      if (!root.isValid(entry)) continue

      const entryScreen = root.screenOf(entry)
      if (entryScreen !== "" && entryScreen !== hostScreen) continue

      const anchor = entry.anchor
      let tray = false
      try {
        const anchorWindow = anchor.Window && anchor.Window.window ? anchor.Window.window : null
        const hostWindow = host.Window && host.Window.window ? host.Window.window : null
        tray = !!anchorWindow && !!hostWindow && anchorWindow !== hostWindow
      } catch (e) {
        tray = false
      }

      let group = 0
      let primary = 0
      let secondary = 0

      if (tray) {
        group = 1
        const trays = BarContext.trays || []
        let handle = null
        for (let i = 0; i < trays.length; i++) {
          const trayItem = trays[i]
          if (trayItem && trayItem.screenName === hostScreen && trayItem.handle && root.isAlive(trayItem.handle)) {
            handle = trayItem.handle
            break
          }
        }
        if (handle) {
          try {
            const point = handle.mapToItem(host, 0, 0)
            primary = vertical ? point.y : point.x
          } catch (e) {
            primary = Number.MAX_SAFE_INTEGER
          }
        } else {
          primary = Number.MAX_SAFE_INTEGER
        }
        secondary = 0
      } else {
        let point = null
        try {
          point = anchor.mapToItem(host, 0, 0)
        } catch (e) {
          continue
        }
        primary = vertical ? point.y : point.x
        secondary = vertical ? point.x : point.y
      }

      list.push({
        name: name,
        group: group,
        primary: primary,
        secondary: secondary
      })
    }

    list.sort(function (a, b) {
      if (a.group !== b.group) return a.group - b.group
      if (a.primary !== b.primary) return a.primary - b.primary
      if (a.secondary !== b.secondary) return a.secondary - b.secondary
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return 0
    })

    return list.map(function (entry) { return entry.name })
  }

  // One-based, as the key that calls it is: `panel position 3` is the third
  // panel from the left.
  function parsePosition(value) {
    const s = String(value === undefined || value === null ? "" : value).trim()
    if (!/^\d+$/.test(s)) return null
    const n = Number(s)
    if (!Number.isFinite(n) || n < 1) return null
    return n
  }

  function togglePosition(position) {
    const parsed = root.parsePosition(position)
    if (parsed === null) return

    const names = root.ordered()
    const index = parsed - 1
    if (!(index >= 0 && index < names.length)) return

    root.toggle(names[index])
  }

  function names() {
    return Object.keys(root.entries).sort()
  }
}
