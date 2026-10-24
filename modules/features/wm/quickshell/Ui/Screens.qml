pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The displays the shell draws on, and which one the compositor is focused on.
//
// Every surface used to be a single window with no `screen`, which meant it
// landed on the primary output and nowhere else. A bar exists per screen now,
// and the surfaces that belong to the focused window (the OSD, notifications,
// the picker, the polkit prompt) follow focus. This is the one place that maps
// Hyprland's monitor names onto Quickshell's screen objects.
//
// `Quickshell.screens` is the authoritative list and changes as displays are
// plugged in and out; `Hyprland.focusedMonitor` is what tells us which of those
// the user is looking at. The fallback to the first screen matters at startup,
// when Hyprland has not answered yet.
QtObject {
  id: root

  readonly property var all: Quickshell.screens

  readonly property var focusedMonitor: Hyprland.focusedMonitor

  readonly property var focused: {
    const name = root.focusedMonitor ? String(root.focusedMonitor.name) : ""
    for (let i = 0; i < root.all.length; i++) {
      if (String(root.all[i].name) === name) return root.all[i]
    }
    return root.all.length > 0 ? root.all[0] : null
  }

  readonly property string focusedName: root.focused ? String(root.focused.name) : ""

  // A stable value that changes whenever the set of outputs does, for code that
  // needs to react to a monitor being unplugged rather than read a screen.
  readonly property string names: {
    const out = []
    for (let i = 0; i < root.all.length; i++) out.push(String(root.all[i].name))
    out.sort()
    return out.join(",")
  }

  function byName(name) {
    if (!name) return null
    const wanted = String(name)
    for (let i = 0; i < root.all.length; i++) {
      if (String(root.all[i].name) === wanted) return root.all[i]
    }
    return null
  }

  // The screen an item is on, or "" when it is not attached to one yet. This is
  // deliberately not a guess: a widget that registers itself from
  // Component.onCompleted has not been shown, so its attached Screen is unset.
  // Callers that key something by display must keep that "unknown" state rather
  // than collapse every bar on the machine onto the focused output.
  function screenNameOf(item) {
    if (!item) return ""

    try {
      const screen = item.Screen
      if (screen) return String(screen.name)

      // An item that is still being built may not have the attached Screen yet,
      // but its window already knows which output it belongs to.
      const win = item.Window && item.Window.window ? item.Window.window : null
      if (win && win.screen) return String(win.screen.name)
    } catch (e) {
      // A destroyed item is not on a screen any more.
    }

    return ""
  }

  // The screen an item is on, for the bar root and the widgets registered
  // against it. An item that has not been shown yet has no screen, in which
  // case the focused one is the only useful guess.
  function nameOf(item) {
    const name = root.screenNameOf(item)
    return name !== "" ? name : root.focusedName
  }

  function widthOf(name) {
    const screen = root.byName(name) || root.focused
    return screen ? screen.width : 1920
  }

  function heightOf(name) {
    const screen = root.byName(name) || root.focused
    return screen ? screen.height : 1080
  }
}
