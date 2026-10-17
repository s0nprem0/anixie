pragma Singleton

import QtQuick
import Quickshell.Io

// Loads bar.json, the file that decides which modules sit in which section.
// Reloads on change, so editing the file updates the bar without a restart.
QtObject {
  id: root

  // Stand-in for a missing or broken bar.json, so a typo in the config never
  // leaves the session without a bar at all.
  readonly property var fallback: ({
    background: "clear",
    layout: {
      left: [{ id: "bar.workspaces" }],
      centerBegin: [],
      center: [{ id: "bar.clock" }],
      centerEnd: [],
      right: [
        { id: "bar.wifi" },
        { id: "bar.audio" },
        { id: "bar.power" }
      ]
    }
  })

  property var config: fallback
  readonly property var layout: config.layout ? config.layout : {}

  function section(name) {
    const entries = layout[name]
    return entries && entries.length ? entries : []
  }

  function reload() {
    let raw = ""
    try {
      raw = configFile.text()
    } catch (e) {
      raw = ""
    }
    if (!raw || raw.trim() === "") return

    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") root.config = parsed
      else console.warn("quickshell bar: bar.json is not an object, keeping the previous config")
    } catch (e) {
      console.warn("quickshell bar: bar.json is not valid JSON, keeping the previous config")
    }
  }

  // A FileView held as a property rather than a child: a QtObject has no
  // default property, so a bare child declaration would never attach.
  property FileView configFile: FileView {
    path: Qt.resolvedUrl("bar.json")
    printErrors: false
    watchChanges: true
    blockLoading: true

    onFileChanged: root.reload()
    Component.onCompleted: root.reload()
  }
}