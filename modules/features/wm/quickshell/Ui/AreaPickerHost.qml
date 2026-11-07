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

  // Output scale (physical/logical), for turning the logical selection
  // into the physical geometry grim expects. Defaults to 1 when the
  // monitors query has not answered yet.
  property real targetScale: 1

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
    root.targetScale = 1
    root.freezePath = ""
    root.openGeneration += 1
    root.shown = true
    root.refreshWindows()
    if (root.freeze) root.captureFreeze()
  }

  function close() {
    root.shown = false
  }

  // Refresh the list of window rects on the target monitor via hyprctl,
  // and the monitor scale alongside it.
  function refreshWindows() {
    if (!root.targetScreen) return
    hyprClients.command = ["hyprctl", "clients", "-j"]
    hyprClients.running = true
    hyprMonitors.command = ["hyprctl", "monitors", "-j"]
    hyprMonitors.running = true
  }

  property Process hyprMonitors: Process {
    running: false
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(this.text || "[]"))
          if (Array.isArray(parsed) && root.targetScreen) {
            for (let i = 0; i < parsed.length; i++) {
              if (String(parsed[i].name || "") === String(root.targetScreen.name)) {
                const s = Number(parsed[i].scale || 1)
                root.targetScale = isFinite(s) && s > 0 ? s : 1
                break
              }
            }
          }
        } catch (e) {
          root.targetScale = 1
        }
      }
    }
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

  // Snap the selection to a window under (x, y) in screen-local
  // logical coords. Window rects are physical (hyprctl), so they
  // are converted through the output scale first.
  function snapToWindow(x, y) {
    if (!root.targetScreen) return
    const scale = root.targetScale > 0 ? root.targetScale : 1
    const sx = root.targetScreen.x * scale
    const sy = root.targetScreen.y * scale
    for (let i = 0; i < root.windowRects.length; i++) {
      const w = root.windowRects[i]
      const cx = (w.at[0] - sx) / scale
      const cy = (w.at[1] - sy) / scale
      const cw = w.size[0] / scale
      const ch = w.size[1] / scale
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
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.freezePath = ""
        root.freeze = false
        Quickshell.execDetached(["notify-send", "-a", "anixie", "Screenshot failed", "Could not freeze the screen."])
      }
    }
  }

  // Run grim (or crop from freeze) on the selection, then hand off.
  // Selection coords are logical; grim wants physical pixels, so
  // everything is scaled through targetScale first.
  function capture() {
    if (!root.targetScreen) { root.close(); return }
    const gen = root.openGeneration
    const scale = root.targetScale > 0 ? root.targetScale : 1
    const x = Math.round(root.selX * scale)
    const y = Math.round(root.selY * scale)
    const w = Math.max(1, Math.round(root.selW * scale))
    const h = Math.max(1, Math.round(root.selH * scale))
    const tmp = "/tmp/anixie-area-" + Date.now() + ".png"
    const clipboard = (root.mode === "clipboard")
    const text = (root.mode === "text")
    const swappy = (root.mode === "swappy")

    root.close()
    if (gen !== root.openGeneration) return

    // The picker is geometry only: for the swappy/clipboard modes
    // the capture itself goes through alexie shot, so both pickers
    // share one capture/destination pipeline (save, copy, annotate,
    // preview, last-capture). Freeze and OCR modes keep their own
    // paths: freeze crops the frozen frame (a fresh grim would not
    // match it), and OCR has no alexie-dest equivalent.
    if (!text && !root.freeze) {
      const geometry = x + "," + y + " " + w + "x" + h
      const dest = clipboard ? "copy" : "annotate"
      const cmd = "{ alexie shot region " + JSON.stringify(geometry) + " " + dest
        + "; } || notify-send -a anixie 'Screenshot failed' 'Nothing was captured.'"
      Quickshell.execDetached(["sh", "-c", cmd])
      return
    }

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

    // Reveal in capture preview after a successful capture, except
    // in swappy mode: swappy is the editor and showing the card as
    // well double-handles the same file.
    if (!text && !swappy) {
      cmd += " && quickshell ipc call capture preview " + JSON.stringify(tmp)
    }

    // A failed capture used to die silently in the chain.
    cmd = "{ " + cmd + "; } || notify-send -a anixie 'Screenshot failed' 'Nothing was captured.'"

    Quickshell.execDetached(["sh", "-c", cmd])
  }
}