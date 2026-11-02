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
    const cfg = BarConfig && BarConfig.config ? BarConfig.config : ({})
    const saved = String((cfg.position !== undefined && cfg.position !== null) ? cfg.position : "")
    const allowed = ["top", "bottom", "left", "right"]
    if (allowed.indexOf(saved) !== -1) return saved
    const themePos = Theme && Theme.position ? String(Theme.position) : "top"
    return allowed.indexOf(themePos) !== -1 ? themePos : "top"
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

  // Maximum dimension the bar uses in the cross-axis / thickness sense.
  readonly property int maxBarSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // The tray widgets, in load order. The display is resolved when one is looked
  // up rather than when it registers: at Component.onCompleted the tray is not
  // on a screen yet, so every bar would key itself to the focused output.
  // `bar tray` then opens the tray on the display the pointer is working on.
  property var trays: []

  function isAlive(item) {
    if (!item) return false
    try {
      const v = item.visible
      return true
    } catch (e) {
      return false
    }
  }

  function pruneTrays() {
    const next = []
    let changed = false
    for (let i = 0; i < root.trays.length; i++) {
      const t = root.trays[i]
      if (!root.isAlive(t)) {
        changed = true
        continue
      }
      next.push(t)
    }
    if (changed) root.trays = next
  }

  function registerTray(item) {
    if (!item) return
    if (!root.isAlive(item)) return

    const next = []
    for (let i = 0; i < root.trays.length; i++) {
      if (root.trays[i] !== item) next.push(root.trays[i])
    }
    next.push(item)
    root.trays = next
    root.pruneTrays()
  }

  function unregisterTray(item) {
    if (!item) return

    const next = []
    let removed = false
    for (let i = 0; i < root.trays.length; i++) {
      if (root.trays[i] === item) {
        removed = true
        continue
      }
      next.push(root.trays[i])
    }
    if (removed) {
      root.trays = next
      root.pruneTrays()
    }
  }

  // Resolved at lookup time. Prefer tray on focused screen; otherwise pick the
  // last registered alive tray deterministically.
  readonly property Item trayItem: {
    try {
      root.pruneTrays()
    } catch (e) {}
    const trays = Array.isArray(root.trays) ? root.trays : []
    const name = Screens ? String(Screens.focusedName || "") : ""
    if (name !== "" && Screens && Screens.screenNameOf) {
      for (let i = trays.length - 1; i >= 0; i--) {
        const t = trays[i]
        if (!root.isAlive(t)) continue
        try {
          if (Screens.screenNameOf(t) === name) return t || null
        } catch (e) {}
      }
    }

    for (let i = trays.length - 1; i >= 0; i--) {
      const t = trays[i]
      if (root.isAlive(t)) return t || null
    }
    return null
  }

  onTraysChanged: root.pruneTrays()
}