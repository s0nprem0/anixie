pragma Singleton

import QtQuick
import "Ui"

// Orientation, read by the bar itself and by every module.
//
// Widgets need to know whether they are on a horizontal or a vertical bar: a
// label that fits beside an icon on a top bar has nowhere to go on a side bar,
// where the bar is only as wide as an icon. Passing this down through a
// singleton keeps it out of every module's constructor.
//
// The value is the saved bar position when one exists, with the Nix-rendered
// Theme as the default. Keeping it here rather than in Theme lets `bar position`
// move the bar without rebuilding, while a fresh install still starts from the
// configured edge.
QtObject {
  id: root

  readonly property string position: {
    const saved = String(BarConfig.config.position || "")
    return ["top", "bottom", "left", "right"].indexOf(saved) === -1 ? Theme.position : saved
  }

  readonly property bool vertical: position === "left" || position === "right"

  // Whether the bar is on screen. Hidden keeps the window itself — and the item
  // every panel anchors to — alive, so a panel opened from a hotkey still has
  // somewhere to attach, and the reserved strip is given back to the workspace.
  // Unmapping the window instead would take the anchors with it and leave the
  // panel with nothing to open against.
  property bool shown: true

  function toggle() {
    shown = !shown
  }

  // How far a module may run before it stops being worth showing.
  readonly property int maxBarSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // The tray widgets, by screen name, so the drawer can be opened by name as
  // well as by click. One per bar: `bar tray` opens the one on the display the
  // pointer is working on, not whichever happened to register last.
  property var trays: ({})

  function registerTray(item) {
    if (!item) return

    const name = Screens.nameOf(item)
    if (!name) return

    const next = {}
    for (const key in root.trays) next[key] = root.trays[key]
    next[name] = item
    root.trays = next
  }

  function unregisterTray(item) {
    if (!item) return

    const name = Screens.nameOf(item)
    let found = root.trays[name] === item ? name : ""
    if (!found) {
      for (const key in root.trays) {
        if (root.trays[key] === item) {
          found = key
          break
        }
      }
    }
    if (!found) return

    const next = {}
    for (const key in root.trays) if (key !== found) next[key] = root.trays[key]
    root.trays = next
  }

  readonly property Item trayItem: {
    const name = Screens.focusedName
    if (root.trays[name]) return root.trays[name]

    const keys = Object.keys(root.trays)
    return keys.length > 0 ? root.trays[keys[0]] : null
  }
}