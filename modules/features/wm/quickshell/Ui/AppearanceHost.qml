pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

QtObject {
  id: root

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/theme"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string wallpapersPath: stateDir + "/wallpapers.json"
  readonly property string wallpaperModePath: stateDir + "/wallpaper-mode"
  readonly property string glassPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/glass"

  property var state: ({})
  property var wallpapers: ({})
  property var library: []
  property string wallpaperMode: "auto"
  property bool glass: true
  property bool videoPaused: false
  property bool busy: false
  property string lastError: ""
  property double libraryLoadedAt: 0
  property bool refreshLibraryAfter: false

  readonly property bool pinned: !!state.pinned
  readonly property var favorites: state.favorites || []
  readonly property string currentName: Theme.name === "wallpaper" ? "Wallpaper" : Theme.name
  readonly property bool currentIsVideo: BackgroundHost.videoFor(Screens.focusedName) || BackgroundHost.video
  readonly property string currentPath: BackgroundHost.pathFor(Screens.focusedName) || BackgroundHost.path
  readonly property string stateJson: JSON.stringify(root.state)

  readonly property string currentThumb: {
    if (root.currentPath === "") return ""
    for (let i = 0; i < root.library.length; i++) {
      if (root.library[i].path === root.currentPath) return String(root.library[i].thumb || "")
    }
    return root.currentIsVideo ? "" : root.currentPath
  }

  readonly property string currentWallpaperName: {
    for (let i = 0; i < root.library.length; i++) {
      if (root.library[i].path === root.currentPath) return String(root.library[i].name || "")
    }
    return root.currentPath === "" ? "None" : (root.currentPath.split("/").pop() || root.currentPath)
  }

  readonly property var rows: {
    const favoriteList = root.favorites || []
    const names = Theme.names().slice()
    const rows = []
    for (let i = 0; i < names.length; i++) {
      const name = names[i]
      const palette = Theme.palettes[name] || ({})
      rows.push({
        name: name,
        colors: palette,
        mode: palette._mode || "dark",
        favorite: favoriteList.indexOf(name) !== -1,
        selected: Theme.name === name
      })
    }
    rows.sort(function (a, b) {
      if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return rows
  }

  property var panelComponent: null

  function panelBuilder() {
    if (root.panelComponent === null) {
      root.panelComponent = Qt.createComponent(Qt.resolvedUrl("../panels/Appearance.qml"))
    }
    return root.panelComponent
  }

  function open() {
    const anchor = PanelHost.focusedBar
    if (!anchor) return
    const component = root.panelBuilder()
    if (!component || component.status !== Component.Ready) {
      root.lastError = component && component.errorString ? component.errorString() : "The appearance panel could not load"
      return
    }

    root.lastError = ""
    root.refreshState()
    if (root.library.length === 0 || Date.now() - root.libraryLoadedAt > 60000) {
      root.refreshLibrary()
    }
    PanelHost.toggleNamed("appearance", anchor, component)
  }

  function toggle() {
    if (PanelHost.isOpen("appearance")) PanelHost.close("appearance")
    else root.open()
  }

  function close() {
    PanelHost.close("appearance")
  }

  function run(args) {
    if (root.busy) return
    root.busy = true
    root.lastError = ""
    root.refreshLibraryAfter = args[0] === "wallpaper" && (args[1] === "add" || args[1] === "set")
    root.action.command = args
    root.action.running = true
  }

  function refreshState() {
    root.stateFile.reload()
    root.wallpapersFile.reload()
    root.modeFile.reload()
    root.glassFile.reload()
    root.videoPausedFile.reload()
  }

  function refreshLibrary() {
    root.libraryProc.running = false
    root.libraryProc.running = true
  }

  function setTheme(name) {
    if (root.busy) return
    Theme.set(name)
    root.run(["theme", "set", name])
  }

  function toggleFavorite(name) {
    root.run(["theme", "favorite", "toggle", name])
  }

  function setPinned(value) {
    root.run(["theme", value ? "pin" : "unpin"])
  }

  function useWallpaper(path) {
    if (path === "generated" || path === "") root.run(["wallpaper", "generated"])
    else root.run(["wallpaper", "use", path])
  }

  function nextWallpaper() {
    root.run(["wallpaper", "next"])
  }

  function previousWallpaper() {
    root.run(["wallpaper", "prev"])
  }

  function setWallpaperMode(mode) {
    root.run(["theme", "wallpaper-mode", mode])
  }

  function toggleGlass() {
    root.run(["glass-toggle"])
  }

  function setBarBackground(mode) {
    BarConfig.setBackground(mode)
  }

  function toggleVideo() {
    root.run(["wallpaper", root.videoPaused ? "resume" : "pause"])
  }

  property Process action: Process {
    running: false
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        root.lastError = "The command did not complete"
        Theme.reload()
      }
      root.refreshState()
      if (root.refreshLibraryAfter) {
        root.refreshLibraryAfter = false
        root.refreshLibrary()
      }
    }
  }

  property Process libraryProc: Process {
    running: false
    // Force a scan: the panel should show files added outside the command, and
    // thumbnails that already exist make the refresh cheap.
    command: ["wallpaper", "library", "--json", "--refresh"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(String(this.text || "[]"))
          if (Array.isArray(parsed)) {
            root.library = parsed
            root.libraryLoadedAt = Date.now()
          }
        } catch (e) {
          root.library = []
        }
      }
    }
  }

  property FileView stateFile: FileView {
    path: Qt.resolvedUrl(root.statePath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      try {
        const parsed = JSON.parse(String(root.stateFile.text() || "{}"))
        if (parsed && typeof parsed === "object") root.state = parsed
      } catch (e) {
      }
    }
    onFileChanged: root.stateFile.reload()
  }

  property FileView wallpapersFile: FileView {
    path: Qt.resolvedUrl(root.wallpapersPath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      try {
        const parsed = JSON.parse(String(root.wallpapersFile.text() || "{}"))
        if (parsed && typeof parsed === "object") root.wallpapers = parsed
      } catch (e) {
      }
    }
    onFileChanged: root.wallpapersFile.reload()
  }

  property FileView modeFile: FileView {
    path: Qt.resolvedUrl(root.wallpaperModePath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      const value = String(root.modeFile.text() || "").trim()
      if (value === "auto" || value === "light" || value === "dark") root.wallpaperMode = value
    }
    onFileChanged: root.modeFile.reload()
  }

  property FileView glassFile: FileView {
    path: Qt.resolvedUrl(root.glassPath)
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: {
      const value = String(root.glassFile.text() || "").trim()
      if (value === "true" || value === "false") root.glass = value === "true"
    }
    onFileChanged: root.glassFile.reload()
  }

  property FileView videoPausedFile: FileView {
    path: Qt.resolvedUrl(root.stateDir + "/video-paused")
    printErrors: false
    blockLoading: true
    watchChanges: true
    onLoaded: root.videoPaused = String(root.videoPausedFile.text() || "").trim() !== ""
    onFileChanged: root.videoPausedFile.reload()
  }

  property Timer preload: Timer {
    interval: 1200
    running: true
    repeat: false
    onTriggered: root.panelBuilder()
  }

  property Timer libraryWarm: Timer {
    interval: 3500
    running: true
    repeat: false
    onTriggered: if (root.library.length === 0) root.refreshLibrary()
  }

  Component.onCompleted: {
    root.stateFile.reload()
    root.wallpapersFile.reload()
    root.modeFile.reload()
    root.glassFile.reload()
    root.videoPausedFile.reload()
  }
}
