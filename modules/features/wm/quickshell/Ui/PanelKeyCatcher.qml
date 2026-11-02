import QtQuick
import ".."

// A focus scope that catches keyboard input for a panel-like surface. Wraps
// the shell's Panel keyboard handling in a reusable component so non-Panel
// surfaces (overlays, popups) can opt into the same key model.
FocusScope {
  id: root

  property var panel: null

  Keys.onPressed: function (event) {
    if (root.panel && typeof root.panel.Keys !== "undefined" && root.panel.Keys.onPressed) {
      root.panel.Keys.onPressed(event)
    }
  }
}
