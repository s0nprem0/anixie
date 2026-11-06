pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// The host for the in-shell area picker: a full-screen overlay that lets the
// user drag out a rectangle (or click to take a whole monitor/window) and then
// captures it with grim, handing the result to swappy, the clipboard, OCR, or
// the capture preview.
QtObject {
  id: root

  property bool shown: false
  property bool clipboardOnly: false
  property string mode: "swappy" // swappy | clipboard | text
  property bool freeze: false
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

  // Window rects on the target monitor (global coords), for hover snapping.
  property var windowRects: []
  property string hoveredWindow: ""

  // Frozen frame path (if freeze mode).
  property string freezePath: ""

  property int openGeneration: 0

  function open(clipboardOnly, mode, freeze, screenName) {
    root.clipboardOnly = !!clipboardOnly
    root.mode = mode ? mode : (clipboardOnly ? "clipboard" : "swappy")
    root.freeze = !!freeze
    if (screenName && Screens.byName) {
      const s = Screens.byName(screenName)
      if (s) root.targetScreen = s
      else root.targetScreen = (Screens && Screens.focused) ? Screens.focused : (Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    } else {
      root.targetScreen = (Screens && Screens.focused) ? Screens.focused : (Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    }
    root.startX = 0
    root.startY = 0
    root.endX = root.targetScreen ? root.targetScreen.width : 0
    root.endY = root.targetScreen ? root.targetScreen.height : 0
    root.windowRects = []
    root.hoveredWindow = ""
    root.freezePath = ""
    root.openGeneration += 1
    root.shown = true
    root.refreshWindows()
    if (root.freeze) root.captureFreeze()
  }

  function close() {
    root.shown = false
  }

  // Refresh the list of window rects on the target monitor via hyprctl.
  function refreshWindows() {
    if (!root.targetScreen) return
    const mon = root.targetScreen.name
    hyprClients.command = ["hyprctl", "clients", "-j"]
    hyprClients.running = true
  }

  property Process hyprClients: Process {
    running: false
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(this.text || "[]"))
          const out = []
          if (Array.isArray(parsed)) {
            for (let i = 0; i < parsed.length; i++) {
              const c = parsed[i]
              if (!c || !c.address) continue
              if (!Array.isArray(c.at) || !Array.isArray(c.size)) continue
              // only windows on the target monitor
              if (c.monitor !== undefined && root.targetScreen) {
                // hyprctl monitor id; match by name if possible via at within screen
              }
              out.push({ klass: String(c.class || c.initialClass || "app"), title: String(c.title || ""), at: c.at, size: c.size })
            }
          }
          root.windowRects = out
        } catch (e) {
          root.windowRects = []
        }
      }
    }
  }

  // Snap the selection to a window under (x, y) in screen-local coords.
  function snapToWindow(x, y) {
    if (!root.targetScreen) return
    const sx = root.targetScreen.x
    const sy = root.targetScreen.y
    for (let i = 0; i < root.windowRects.length; i++) {
      const w = root.windowRects[i]
      const cx = w.at[0] - sx
      const cy = w.at[1] - sy
      const cw = w.size[0]
      const ch = w.size[1]
      if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
        root.startX = cx
        root.startY = cy
        root.endX = cx + cw
        root.endY = cy + ch
        root.hoveredWindow = w.klass + (w.title ? " — " + w.title : "")
        return true
      }
    }
    root.hoveredWindow = ""
    return false
  }

  // Freeze the screen to a temp image.
  function captureFreeze() {
    const gen = root.openGeneration
    const path = "/tmp/anixie-area-freeze-" + gen + ".png"
    root.freezePath = path
    freezeProc.command = ["grim", path]
    freezeProc.running = true
  }

  property Process freezeProc: Process {
    running: false
    command: ["true"]
    onExited: function () { /* nothing; path stored */ }
  }

  // Run grim (or crop from freeze) on the selection, then hand off.
  function capture() {
    if (!root.targetScreen) { root.close(); return }
    const gen = root.openGeneration
    const x = Math.round(root.selX)
    const y = Math.round(root.selY)
    const w = Math.max(1, Math.round(root.selW))
    const h = Math.max(1, Math.round(root.selH))
    const tmp = "/tmp/anixie-area-" + Date.now() + ".png"
    const clipboard = (root.mode === "clipboard")
    const text = (root.mode === "text")

    root.close()
    if (gen !== root.openGeneration) return

    let cmd
    if (root.freeze && root.freezePath) {
      // crop from the frozen frame with imagemagick
      cmd = "magick " + JSON.stringify(root.freezePath) + " -crop " + w + "x" + h + "+" + x + "+" + y + " +repage " + JSON.stringify(tmp)
    } else {
      const geometry = x + "," + y + " " + w + "x" + h
      cmd = "grim -g " + JSON.stringify(geometry) + " " + JSON.stringify(tmp)
    }

    if (text) {
      cmd += " && tesseract " + JSON.stringify(tmp) + " stdout | wl-copy"
        + " && notify-send -a anixie 'Text extracted' 'Copied to clipboard'"
    } else if (clipboard) {
      cmd += " && wl-copy --type image/png < " + JSON.stringify(tmp)
        + " && notify-send -a anixie 'Screenshot taken' 'Copied to clipboard'"
    } else {
      cmd += " && swappy -f " + JSON.stringify(tmp)
    }

    // Reveal in capture preview after a successful capture (non-text).
    if (!text) {
      cmd += " && quickshell ipc call capture preview " + JSON.stringify(tmp)
    }

    Quickshell.execDetached(["sh", "-c", cmd])
  }
}