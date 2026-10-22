pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Screen time for the current day, sampled once every ten seconds.
//
// It lives in the shell because the two facts it needs are already here: the
// focused toplevel and the idle monitor. No polling of hyprctl, no second
// process, and the same answer the bar and the panel draw.
//
// One JSON file per day under the state directory. The file is the durable copy;
// the shell keeps the live numbers and rewrites the file once a minute. A shell
// restart therefore loses at most the last minute, which is a better trade than
// a write every ten seconds.
QtObject {
  id: root

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/screentime"

  property string day: root.localDay()
  property var apps: ({})
  property int idleSeconds: 0
  property int activeSeconds: 0
  property bool ready: false
  property string currentApp: ""
  property int secondsSinceSave: 0

  readonly property int totalSeconds: root.activeSeconds + root.idleSeconds
  readonly property string todayLabel: root.day

  function localDay(date) {
    const d = date || new Date()
    const month = String(d.getMonth() + 1).padStart(2, "0")
    const day = String(d.getDate()).padStart(2, "0")
    return d.getFullYear() + "-" + month + "-" + day
  }

  function pathFor(day) {
    return root.stateDir + "/" + day + ".json"
  }

  function formatDuration(seconds) {
    const total = Math.max(0, Math.round(seconds))
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  function appLabel(app) {
    let name = String(app || "")
    if (name === "" || name === "unknown") return "Other"

    const parts = name.split(".")
    if (parts.length > 1 && parts[parts.length - 1].toLowerCase() === "desktop") parts.pop()
    name = parts[parts.length - 1].replace(/[-_]+/g, " ").trim()
    if (name === "") return "Other"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  function topApps(limit) {
    const list = []
    for (const app in root.apps) {
      const seconds = Number(root.apps[app]) || 0
      if (seconds > 0) list.push({ app: app, seconds: seconds })
    }
    list.sort(function (a, b) { return b.seconds - a.seconds })
    return list.slice(0, limit || 5)
  }

  function json() {
    return JSON.stringify({
      date: root.day,
      apps: root.apps,
      idle: root.idleSeconds,
      active: root.activeSeconds
    })
  }

  function absorb(text) {
    try {
      const data = JSON.parse(String(text || ""))
      root.apps = (data && typeof data.apps === "object" && data.apps !== null) ? data.apps : ({})
      root.idleSeconds = Number(data && data.idle) || 0
      root.activeSeconds = Number(data && data.active) || 0
      root.ready = true
    } catch (e) {
      root.apps = ({})
      root.idleSeconds = 0
      root.activeSeconds = 0
      root.ready = true
    }
  }

  function load() {
    root.todayFile.reload()
  }

  function save() {
    root.secondsSinceSave = 0
    Quickshell.execDetached([
      "/bin/sh", "-c",
      "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/.$3.tmp\" && mv \"$1/.$3.tmp\" \"$1/$3.json\"",
      "screentime", root.stateDir, root.json(), root.day
    ])
  }

  function reset() {
    root.apps = ({})
    root.idleSeconds = 0
    root.activeSeconds = 0
    root.save()
  }

  function tick() {
    const today = root.localDay()
    if (today !== root.day) {
      root.save()
      root.day = today
      root.apps = ({})
      root.idleSeconds = 0
      root.activeSeconds = 0
      root.load()
      return
    }

    const idle = root.monitor.isIdle || LockHost.locked
    if (idle) {
      root.idleSeconds += 10
      root.currentApp = ""
    } else {
      const toplevel = ToplevelManager.activeToplevel
      const app = toplevel ? String(toplevel.appId || "") : ""
      const key = app !== "" ? app.toLowerCase() : "unknown"

      const next = {}
      for (const name in root.apps) next[name] = root.apps[name]
      next[key] = (Number(next[key]) || 0) + 10
      root.apps = next
      root.activeSeconds += 10
      root.currentApp = key
    }

    root.secondsSinceSave += 10
    if (root.secondsSinceSave >= 60) root.save()
  }

  property IdleMonitor monitor: IdleMonitor {
    timeout: 60
    respectInhibitors: true
  }

  property FileView todayFile: FileView {
    path: root.pathFor(root.day)
    printErrors: false
    blockLoading: true
    onLoaded: root.absorb(this.text())
  }

  property Timer ticker: Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  Component.onCompleted: {
    root.day = root.localDay()
    root.load()
  }
}
