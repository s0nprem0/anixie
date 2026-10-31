pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "fuzzy.js" as Fuzzy

// The clipboard's data and actions: the history from cliphist, the filter, the
// selection, and the preview the window draws beside the list.
//
// The window is Clipboard.qml and the IPC target is in ShellIpc. Everything
// that talks to cliphist is here, through the `clipboard` command, so the
// shell does not need to know where the binary lives or how an entry with tabs
// in its preview is quoted.
//
// Preview decoding is on demand and debounced: moving down a list of eighty
// entries should not decode eighty images, and the selection that stops moving
// is the only one worth reading.
QtObject {
  id: root

  property bool shown: false
  property int session: 0
  property string query: ""
  property var entries: []
  property var filtered: []
  property int selected: 0

  property string previewKind: ""
  property string previewText: ""
  property string previewImage: ""
  property bool previewLoading: false

  property bool busy: false
  property string lastError: ""
  property bool largePreview: false

  readonly property var current: {
    if (root.selected < 0 || root.selected >= root.filtered.length) return null
    return root.filtered[root.selected]
  }

  function isFile(text) {
    const value = String(text || "").trim()
    return value.indexOf("/") === 0 || value.indexOf("file://") === 0 || value.indexOf("~/") === 0
  }

  function cleanPath(text) {
    let value = String(text || "").trim()
    if (value.indexOf("file://") === 0) value = value.slice(7)
    if (value.indexOf("~/") === 0) value = Quickshell.env("HOME") + value.slice(1)
    return value
  }

  // cliphist's preview keeps control characters from the original text; they
  // are not readable in a one-line row and can move the cursor around when
  // drawn, so they become spaces here.
  function clean(text) {
    return String(text || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  }

  function imageLabel(preview) {
    const match = String(preview).match(/^\[\[ binary data (.+) \]\]$/)
    return match ? "Image · " + match[1] : "Image"
  }

  function isImageLine(preview) {
    return String(preview).indexOf("[[ binary data ") === 0
  }

  function parseList(text) {
    const out = []
    const lines = String(text || "").split("\n")

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (line === "") continue

      const tab = line.indexOf("\t")
      if (tab <= 0) continue

      const id = line.slice(0, tab)
      const preview = line.slice(tab + 1)
      const image = root.isImageLine(preview)

      out.push({
        id: id,
        label: image ? root.imageLabel(preview) : root.clean(preview),
        image: image,
        imagePath: ""
      })
    }

    root.entries = out
  }

  function applyFilter(keepId) {
    const q = root.query.trim()
    let out = []

    if (q === "") {
      out = root.entries.slice()
    } else {
      const result = Fuzzy.filter(root.entries, q)
      for (let i = 0; i < result.length; i++) out.push(result[i].row)
    }

    root.filtered = out

    let index = 0
    if (keepId) {
      for (let j = 0; j < out.length; j++) {
        if (out[j].id === keepId) { index = j; break }
      }
    }
    root.selected = Math.max(0, Math.min(index, out.length - 1))
    root.requestPreview()
  }

  function setQuery(text) {
    root.query = String(text || "")
    root.applyFilter("")
  }

  function select(index) {
    if (index < 0 || index >= root.filtered.length) return
    if (root.selected === index) return
    root.selected = index
    root.requestPreview()
  }

  function move(delta) {
    if (root.filtered.length === 0) return
    root.select(Math.max(0, Math.min(root.filtered.length - 1, root.selected + delta)))
  }

  function first() {
    root.select(0)
  }

  function last() {
    root.select(root.filtered.length - 1)
  }

  function clearPreview() {
    root.previewKind = ""
    root.previewText = ""
    root.previewImage = ""
    root.previewLoading = false
    if (textDecode.running) textDecode.running = false
    if (imageDecode.running) imageDecode.running = false
  }

  property Timer previewTimer: Timer {
    interval: 60
    onTriggered: root.updatePreview()
  }

  function requestPreview() {
    root.previewTimer.stop()
    if (!root.current) {
      root.clearPreview()
      return
    }
    root.previewTimer.restart()
  }

  function updatePreview() {
    const entry = root.current
    if (!entry) {
      root.clearPreview()
      return
    }

    root.previewText = ""
    root.previewImage = ""
    root.previewLoading = false
    if (textDecode.running) textDecode.running = false
    if (imageDecode.running) imageDecode.running = false

    if (entry.image) {
      root.previewKind = "image"

      if (entry.imagePath !== "") {
        root.previewImage = entry.imagePath
        return
      }

      root.previewLoading = true
      imageDecode.command = ["clipboard", "--image", entry.id]
      imageDecode.decodingId = entry.id
      imageDecode.running = false
      imageDecode.running = true
      return
    }

    root.previewKind = root.isFile(entry.label) ? "file" : "text"
    root.previewText = entry.label

    // cliphist's list preview is truncated at about a hundred characters. The
    // full entry is only worth another process when there is more of it than
    // the row already shows; a two-word clip is its own preview.
    if (!root.isFile(entry.label) && entry.label.length < 80) return

    root.previewLoading = true
    textDecode.command = ["clipboard", "--text", entry.id]
    textDecode.decodingId = entry.id
    textDecode.running = false
    textDecode.running = true
  }

  // ---- reading the history ----

  function open() {
    root.session += 1
    root.shown = true
    root.query = ""
    root.selected = 0
    root.busy = false
    root.lastError = ""
    root.clearPreview()
    root.load(0)
  }

  function dismiss() {
    root.shown = false
    previewTimer.stop()
    if (listProc.running) listProc.running = false
    if (imagesProc.running) imagesProc.running = false
    if (textDecode.running) textDecode.running = false
    if (imageDecode.running) imageDecode.running = false
  }

  function load(index) {
    listProc.keepIndex = Number(index || 0)
    listProc.running = false
    listProc.running = true
  }

  property Process listProc: Process {
    command: ["clipboard", "--list"]
    running: false

    property int keepIndex: 0

    stdout: StdioCollector {
      onStreamFinished: {
        root.parseList(this.text)
        root.applyFilter("")
        if (root.filtered.length > 0) {
          root.selected = Math.max(0, Math.min(root.listProc.keepIndex, root.filtered.length - 1))
        }
        root.requestPreview()

        if (root.shown) {
          root.imagesProc.running = false
          root.imagesProc.running = true
        }
      }
    }
  }

  // The thumbnails for the list, decoded once per open. An entry past the first
  // forty images has no thumbnail; the preview still decodes it when chosen.
  property Process imagesProc: Process {
    command: ["clipboard", "--images"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.shown) return

        const map = {}
        const lines = String(this.text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (line === "") continue
          const tab = line.indexOf("\t")
          if (tab <= 0) continue
          map[line.slice(0, tab)] = line.slice(tab + 1)
        }

        const keepId = root.current ? root.current.id : ""
        const next = []
        for (let j = 0; j < root.entries.length; j++) {
          const entry = root.entries[j]
          next.push({
            id: entry.id,
            label: entry.label,
            image: entry.image,
            imagePath: map[entry.id] || entry.imagePath
          })
        }

        root.entries = next
        root.applyFilter(keepId)

        if (root.current && root.current.image && root.previewImage === "" && root.current.imagePath !== "") {
          root.previewImage = root.current.imagePath
          root.previewLoading = false
        }
      }
    }
  }

  // ---- preview decodes ----

  property Process textDecode: Process {
    command: ["true"]
    running: false
    property string decodingId: ""

    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.current || root.current.id !== root.textDecode.decodingId) return
        root.previewText = String(this.text || "")
        root.previewKind = root.isFile(root.previewText) ? "file" : "text"
        root.previewLoading = false
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 && root.current && root.current.id === root.textDecode.decodingId) {
        root.previewLoading = false
      }
    }
  }

  property Process imageDecode: Process {
    command: ["true"]
    running: false
    property string decodingId: ""
    stderr: StdioCollector { id: imageError }

    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.current || root.current.id !== root.imageDecode.decodingId) return
        const path = String(this.text || "").trim()
        if (path !== "") {
          root.previewImage = path
          root.previewLoading = false
        }
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) root.previewLoading = false
    }
  }

  // ---- actions ----

  function copyCurrent() {
    const entry = root.current
    if (!entry || root.busy) return

    root.busy = true
    root.lastError = ""
    copyProc.command = ["clipboard", "--copy", entry.id]
    copyProc.running = false
    copyProc.running = true
  }

  function deleteCurrent() {
    const entry = root.current
    if (!entry || root.busy) return

    root.busy = true
    root.lastError = ""
    deleteProc.keepIndex = root.selected
    deleteProc.command = ["clipboard", "--delete", entry.id]
    deleteProc.running = false
    deleteProc.running = true
  }

  function wipe() {
    if (root.busy) return

    root.busy = true
    root.lastError = ""
    wipeProc.running = false
    wipeProc.running = true
  }

  function openFile() {
    const text = root.previewText !== "" ? root.previewText : (root.current ? root.current.label : "")
    const path = root.cleanPath(text)
    if (path !== "") Quickshell.execDetached(["xdg-open", path])
  }

  property Process copyProc: Process {
    command: ["true"]
    running: false
    stderr: StdioCollector { id: copyError }

    onExited: function (exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.dismiss()
        return
      }
      const message = String(copyError.text || "").trim().split("\n")[0]
      root.lastError = message !== "" ? message : "Could not copy the entry"
    }
  }

  property Process deleteProc: Process {
    command: ["true"]
    running: false
    property int keepIndex: 0
    stderr: StdioCollector { id: deleteError }

    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        const message = String(deleteError.text || "").trim().split("\n")[0]
        root.lastError = message !== "" ? message : "Could not delete the entry"
      }
      root.load(root.deleteProc.keepIndex)
    }
  }

  property Process wipeProc: Process {
    command: ["clipboard", "--wipe"]
    running: false
    stderr: StdioCollector { id: wipeError }

    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        const message = String(wipeError.text || "").trim().split("\n")[0]
        root.lastError = message !== "" ? message : "Could not clear the history"
      }
      root.load(0)
    }
  }

  // ---- what the preview says ----

  readonly property string typeLabel: {
    if (!root.current) return ""
    if (root.previewKind === "image") return "Image"
    if (root.previewKind === "file") return "File"
    return "Text (" + root.previewText.length + " chars)"
  }

  readonly property int lineCount: {
    if (root.previewText === "") return 0
    return root.previewText.split("\n").length
  }

  readonly property int wordCount: {
    const text = root.previewText.trim()
    if (text === "") return 0
    return text.split(/\s+/).length
  }

  readonly property string statLabel: {
    if (!root.current) return ""
    if (root.previewKind === "image") return "Image"
    if (root.previewKind === "file") return "File path"
    return root.lineCount + " lines, " + root.wordCount + " words"
  }
}
