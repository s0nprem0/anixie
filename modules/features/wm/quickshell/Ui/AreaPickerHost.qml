pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// The host for the in-shell area picker: a full-screen overlay that lets the
// user drag out a rectangle (or click to take the whole monitor) and then
// captures it with grim, handing the result to swappy for annotation or to the
// clipboard.
//
// Distinct from PickHost, which drives the launcher/command picker. This one
// owns only the selection geometry and the capture hand-off.
QtObject {
  id: root

  property bool shown: false
  property bool clipboardOnly: false
  property var targetScreen: null

  // Selection geometry, in the target screen's local coordinates.
  property real startX: 0
  property real startY: 0
  property real endX: 0
  property real endY: 0

  readonly property real selX: Math.min(root.startX, root.endX)
  readonly property real selY: Math.min(root.startY, root.endY)
  readonly property real selW: Math.abs(root.startX - root.endX)
  readonly property real selH: Math.abs(root.startY - root.endY)

  property int openGeneration: 0

  function open(clipboardOnly) {
    root.clipboardOnly = !!clipboardOnly
    root.targetScreen = (Screens && Screens.focused) ? Screens.focused : (Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    root.startX = 0
    root.startY = 0
    root.endX = root.targetScreen ? root.targetScreen.width : 0
    root.endY = root.targetScreen ? root.targetScreen.height : 0
    root.openGeneration += 1
    root.shown = true
  }

  function close() {
    root.shown = false
  }

  // Run grim on the selection, then hand off to swappy or wl-copy.
  function capture() {
    if (!root.targetScreen) {
      root.close()
      return
    }
    const gen = root.openGeneration
    const screenName = root.targetScreen.name
    const x = Math.round(root.selX)
    const y = Math.round(root.selY)
    const w = Math.max(1, Math.round(root.selW))
    const h = Math.max(1, Math.round(root.selH))
    const tmp = "/tmp/anixie-area-" + Date.now() + ".png"
    const geometry = x + "," + y + " " + w + "x" + h
    const clipboard = root.clipboardOnly

    root.close()
    if (gen !== root.openGeneration) return

    const cmd = "grim -g " + JSON.stringify(geometry) + " " + JSON.stringify(tmp)
      + " && " + (clipboard
        ? "wl-copy --type image/png < " + JSON.stringify(tmp)
        : "swappy -f " + JSON.stringify(tmp))
    Quickshell.execDetached(["sh", "-c", cmd])
  }
}