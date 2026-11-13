pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property bool shown: false
  property var items: []

  function toggle() {
    if (root.shown) root.hide()
    else root.show()
  }

  function show() {
    refresh()
    root.shown = true
  }

  function hide() {
    root.shown = false
  }

  function refresh() {
    refreshProc.running = false
    refreshProc.running = true
  }

  function reveal(path) {
    if (path === "") return
    try {
      Quickshell.execDetached(["quickshell", "ipc", "call", "capture", "preview", path])
    } catch (e) {}
    root.hide()
  }

  function revealCopyFailed(path) {
    if (path === "") return
    try {
      Quickshell.execDetached(["quickshell", "ipc", "call", "capture", "previewCopyFailed", path])
    } catch (e) {}
    root.hide()
  }

  function openPath(path) {
    if (path === "") return
    Quickshell.execDetached(["xdg-open", path])
    root.hide()
  }

  function openFolder(path) {
    if (path === "") return
    Quickshell.execDetached(["sh", "-c", "dir=$(dirname \"$1\"); if command -v dbus-send >/dev/null 2>&1; then dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:\"file://$(realpath -- \"$1\" 2>/dev/null || printf '%s' \"$1\")\" string:\"\" >/dev/null 2>&1 && exit 0; fi; xdg-open \"$dir\" >/dev/null 2>&1", "sh", path])
    root.hide()
  }

  function copyPath(path) {
    if (path === "") return
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy --type text/plain", "sh", path])
  }

  function copyUri(path) {
    if (path === "") return
    Quickshell.execDetached(["sh", "-c", "uri=\"file://$(realpath -- \"$1\" 2>/dev/null || printf '%s' \"$1\")\"; printf '%s\n' \"$uri\" | wl-copy --type text/uri-list", "sh", path])
  }

  function editPath(path) {
    if (path === "") return
    Quickshell.execDetached(["sh", "-c", "test -f \"$1\" && exec satty --filename \"$1\" --output-filename \"$1\" --initial-tool crop", "sh", path])
    root.hide()
  }

  function transcodePath(path) {
    if (path === "") return
    Quickshell.execDetached(["transcode", path])
    root.hide()
  }

  property Process refreshProc: Process {
    command: ["sh", "-c", "if command -v alexie >/dev/null 2>&1; then alexie shot db list --json; else dir=${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots; [ -d \"$dir\" ] || dir=$HOME/Pictures/Screenshots; find \"$dir\" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) -printf '%T@ %p\\n' 2>/dev/null | sort -nr | head -20 | awk '{sub($1\" \",\"\"); print}'; fi"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const raw = String(this.text).trim()
        if (raw === "") {
          root.items = []
          return
        }
        if (raw.charAt(0) === "[") {
          try {
            const assets = JSON.parse(raw)
            const out = []
            for (let i = 0; i < assets.length; i++) {
              const asset = assets[i]
              if (asset && !asset.deleted && asset.source_path) out.push(String(asset.source_path))
            }
            root.items = out
            return
          } catch (e) {}
        }
        const lines = raw.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
          const p = lines[i].trim()
          if (p !== "") out.push(p)
        }
        root.items = out
      }
    }
  }
}
