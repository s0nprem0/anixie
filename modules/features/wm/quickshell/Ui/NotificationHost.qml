pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "NotificationText.js" as NotificationText

// The notification daemon. The shell owns org.freedesktop.Notifications
// itself, so there is no second process to keep in step with it — the same
// arrangement the reference uses.
//
// A notification is tracked while it is on screen, which is what puts it in
// `trackedNotifications` for the popups to draw and for anything to dismiss.
// One arriving while silencing is on is left untracked, so it is dropped as a
// popup — but it is still written to history, since silencing means "do not
// interrupt me", not "pretend it never happened".
//
// NotificationStore mirrors each notification to disk for as long as it is
// here, and archives the file once it goes, which is what gives the shell a
// history it did not have before.
QtObject {
  id: root

  property bool doNotDisturb: false

  // Silencing survives a shell restart. A restart is invisible to the user —
  // updates perform one — and coming back unsilenced turns the next batch of
  // messages into popups the user had explicitly asked not to see.
  readonly property string dndPath: NotificationStore.stateDir + "/dnd"

  // Guards the write that hydrating the saved value would otherwise trigger.
  property bool _hydrating: false
  property string _pendingDnd: ""

  function loadDnd() {
    let text = ""
    try {
      text = String(root.dndFile.text()).trim()
    } catch (e) {
      // No file yet: the first run starts unsilenced.
    }
    if (text === "") return

    root._hydrating = true
    root.doNotDisturb = text === "on" || text === "true" || text === "1"
    root._hydrating = false
  }

  // Written through a process and a file adapter, the same way the bar's layout
  // is saved: the directory is made first, because a write into a directory that
  // does not exist yet is a drop that silently does nothing.
  function saveDnd() {
    root._pendingDnd = root.doNotDisturb ? "on\n" : "off\n"
    root.dndMkdir.running = false
    root.dndMkdir.running = true
  }

  property FileView dndFile: FileView {
    path: Qt.resolvedUrl(root.dndPath)
    printErrors: false
    blockLoading: true
    atomicWrites: true

    Component.onCompleted: root.loadDnd()
  }

  property Process dndMkdir: Process {
    command: ["mkdir", "-p", NotificationStore.stateDir]
    running: false

    onExited: {
      if (root._pendingDnd === "") return
      root.dndFile.setText(root._pendingDnd)
      root._pendingDnd = ""
    }
  }

  // ---- snoozes ----
  //
  // A snooze is a time-bounded silence per sender, plus one for everything. DND
  // is the explicit switch; these are the "not now" choices a card's zzz opens.
  // They live beside DND so a shell restart does not bring every notification
  // back in the middle of the quiet the user asked for.
  property double globalSnoozeUntil: 0
  property var snoozes: ({})

  readonly property string snoozesPath: NotificationStore.stateDir + "/snoozes.json"
  property bool _hydratingSnoozes: false
  property string _pendingSnoozes: ""

  function sourceOf(notification) {
    return String(notification && notification.appName ? notification.appName : "").toLowerCase()
  }

  function loadSnoozes() {
    let text = ""
    try {
      text = String(root.snoozesFile.text()).trim()
    } catch (e) {
    }
    if (text === "") return

    let parsed = null
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!parsed || typeof parsed !== "object") return

    root._hydratingSnoozes = true
    const now = Date.now() / 1000
    const globalUntil = Number(parsed.globalUntil || 0)
    root.globalSnoozeUntil = globalUntil > now ? globalUntil : 0
    const sources = parsed.sources && typeof parsed.sources === "object" ? parsed.sources : {}
    const next = {}
    for (const key in sources) {
      const until = Number(sources[key] || 0)
      if (until > now) next[String(key)] = until
    }
    root.snoozes = next
    root._hydratingSnoozes = false
  }

  function saveSnoozes() {
    root._pendingSnoozes = JSON.stringify({
      globalUntil: root.globalSnoozeUntil,
      sources: root.snoozes
    }) + "\n"
    root.snoozesMkdir.running = false
    root.snoozesMkdir.running = true
  }

  property FileView snoozesFile: FileView {
    path: Qt.resolvedUrl(root.snoozesPath)
    printErrors: false
    blockLoading: true
    atomicWrites: true

    Component.onCompleted: root.loadSnoozes()
  }

  property Process snoozesMkdir: Process {
    command: ["mkdir", "-p", NotificationStore.stateDir]
    running: false

    onExited: {
      if (root._pendingSnoozes === "") return
      root.snoozesFile.setText(root._pendingSnoozes)
      root._pendingSnoozes = ""
    }
  }

  // Trims expired entries without asking the user to do anything. The file is
  // rewritten only when something actually went away.
  readonly property bool hasSnoozes: {
    const now = Date.now() / 1000
    if (root.globalSnoozeUntil > now) return true
    for (const key in root.snoozes) if (Number(root.snoozes[key] || 0) > now) return true
    return false
  }

  property Timer snoozeTicker: Timer {
    interval: 30000
    repeat: true
    running: root.hasSnoozes
    onTriggered: root.pruneSnoozes()
  }

  function pruneSnoozes() {
    const now = Date.now() / 1000
    const next = {}
    let changed = root.globalSnoozeUntil > 0 && root.globalSnoozeUntil <= now
    if (changed) root.globalSnoozeUntil = 0
    for (const key in root.snoozes) {
      if (Number(root.snoozes[key] || 0) > now) next[key] = root.snoozes[key]
      else changed = true
    }
    if (!changed) return
    root.snoozes = next
    root.saveSnoozes()
  }

  function snoozeOptions() {
    return [
      { label: "For 15 minutes", seconds: 15 * 60 },
      { label: "For 1 hour", seconds: 60 * 60 },
      { label: "Until tomorrow 8am", seconds: root.untilTomorrow() }
    ]
  }

  function untilTomorrow() {
    const now = new Date()
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0, 0)
    return Math.max(60, Math.round((next.getTime() - now.getTime()) / 1000))
  }

  function snooze(source, seconds) {
    const value = Number(seconds)
    if (!isFinite(value) || value <= 0) return

    const now = Date.now() / 1000
    const until = now + value
    const next = {}
    for (const key in root.snoozes) {
      if (Number(root.snoozes[key] || 0) > now) next[key] = root.snoozes[key]
    }

    if (source === "*") root.globalSnoozeUntil = until
    else if (source !== "") next[String(source).toLowerCase()] = until

    root.snoozes = next
    root.saveSnoozes()
    root.dismissSource(source)
    root.closeReplay()
  }

  function unsnooze(source) {
    if (source === "*") {
      root.globalSnoozeUntil = 0
    } else {
      const next = {}
      for (const key in root.snoozes) if (key !== source) next[key] = root.snoozes[key]
      root.snoozes = next
    }
    root.saveSnoozes()
  }

  function dismissSource(source) {
    const wanted = String(source || "").toLowerCase()
    for (let i = root.tracked.length - 1; i >= 0; i--) {
      const item = root.tracked[i]
      if (wanted === "*" || root.sourceOf(item) === wanted) item.dismiss()
    }
  }

  function quietSources() {
    const now = Date.now() / 1000
    const out = []
    if (root.globalSnoozeUntil > now) out.push({ key: "*", label: "Everything", until: root.globalSnoozeUntil })
    for (const key in root.snoozes) {
      const until = Number(root.snoozes[key] || 0)
      if (until > now) out.push({ key: key, label: key, until: until })
    }
    return out
  }

  property bool codesBypassQuiet: true

  function codeBypass(notification) {
    if (!root.codesBypassQuiet || !notification) return false
    const text = String(notification.summary || "") + "\n" + String(notification.body || "")
    return NotificationText.code(text) !== ""
  }

  function isQuiet(notification) {
    if (root.bypassesSilencing(notification)) return false
    if (root.codeBypass(notification)) return false
    const now = Date.now() / 1000
    if (root.doNotDisturb) return true
    if (root.globalSnoozeUntil > now) return true
    return Number(root.snoozes[root.sourceOf(notification)] || 0) > now
  }

  // Which senders are allowed through silencing. Critical urgency by itself is
  // not a reason: chat applications mark everything critical to force their way
  // in front of the user. Trusted are our own confirmations for something the
  // user just did — reminders, a screenshot, a recording, an output switch — and
  // bare-CLI emergencies, which are almost always a system script rather than a
  // brand. `anixie-action` is the default `notify` sends for exactly those.
  readonly property var ownApps: [
    "anixie-action", "audio", "battery", "capture", "nixos", "record", "reminders", "sessions"
  ]

  function bypassesSilencing(notification) {
    const app = String(notification.appName || "").toLowerCase()

    if (root.ownApps.indexOf(app) !== -1) return true
    return app === "notify-send" && notification.urgency === NotificationUrgency.Critical
  }

  // Replayed history is deliberately separate from `tracked`: those
  // notifications are gone, their senders' actions are dead, and they must not
  // be swept into history a second time. The popup window draws either the live
  // stack or this replay, never both.
  property var replayEntries: []
  property bool replaying: false

  readonly property var tracked: server.trackedNotifications ? server.trackedNotifications.values : []

  // Newest first, so the popup column reads top-down as most recent.
  readonly property var stacked: {
    const list = []
    for (let i = root.tracked.length - 1; i >= 0; i--) list.push(root.tracked[i])
    return list
  }

  // Notifications from one application, kept together wherever they sit in the
  // stack. The popup draws each one as its own card; the grouping only decides
  // the order, so a chat's messages stay beside each other instead of being
  // split by whatever arrived in between.
  readonly property var groups: {
    const out = []
    const byApp = ({})

    for (const item of root.stacked) {
      const app = String(item.appName || "").toLowerCase()
      const existing = byApp[app]

      if (existing) {
        existing.items.push(item)
        continue
      }

      const next = { app: app, items: [item] }
      byApp[app] = next
      out.push(next)
    }

    return out
  }

  // The groups flattened back into one list, in group order. The popup draws
  // these as individual cards rather than collapsing a group to its newest one:
  // a chat that sends three messages should show three cards, not hide two
  // behind a count.
  readonly property var groupedItems: {
    const out = []
    for (const group of root.groups) for (const item of group.items) out.push(item)
    return out
  }

  function dismiss(item) {
    if (item) item.dismiss()
  }

  function dismissAll() {
    for (let i = root.tracked.length - 1; i >= 0; i--) root.tracked[i].dismiss()
  }

  // What silencing may take with it: everything except the messages that are
  // allowed through it. Turning DND on must not throw away the critical alert
  // that was meant to survive it.
  function dismissSilenced() {
    for (let i = root.tracked.length - 1; i >= 0; i--) {
      const item = root.tracked[i]
      if (!root.bypassesSilencing(item) && !root.codeBypass(item)) item.dismiss()
    }
  }

  function sameNotification(a, b) {
    return String(a.appName || "").toLowerCase() === String(b.appName || "").toLowerCase()
      && String(a.summary || "") === String(b.summary || "")
      && String(a.body || "") === String(b.body || "")
  }

  // Show the newest history entries for a few seconds. `NotificationStore` reads
  // from disk asynchronously, so the popup is only made visible once there is
  // something to draw.
  function replay() {
    NotificationStore.refresh(function (entries) {
      root.replayEntries = entries.slice(0, 10)
      root.replaying = root.replayEntries.length > 0
      if (root.replaying) root.replayTimer.restart()
    })
  }

  function closeReplay() {
    root.replayTimer.stop()
    root.replayEntries = []
    root.replaying = false
  }

  function dismissReplay(entry) {
    const next = []
    for (const item of root.replayEntries) if (item !== entry) next.push(item)
    root.replayEntries = next
    if (next.length === 0) root.closeReplay()
  }

  // ---- click routing ----
  //
  // A chat notification usually carries no action: clicking it should take you
  // to the window that sent it, not just hide the card. `hyprctl clients` is
  // needed because this build's toplevels do not expose a class; it runs only on
  // a click, never while notifications are arriving.
  property var pendingFocus: null

  function activate(notification, link) {
    const app = String(notification && (notification.appName || notification.app) ? (notification.appName || notification.app) : "")
    root.focusSource(app, String(link || ""))
  }

  function focusSource(app, link) {
    root.pendingFocus = { app: String(app || "").toLowerCase(), link: String(link || "") }
    root.focusClients.running = false
    root.focusClients.running = true
  }

  function focusFrom(text) {
    const pending = root.pendingFocus
    root.pendingFocus = null
    if (!pending) return

    let clients = []
    try {
      clients = JSON.parse(String(text || ""))
    } catch (e) {
      clients = []
    }
    if (!Array.isArray(clients)) clients = []

    const wanted = String(pending.app || "")
    let best = null
    for (let i = 0; i < clients.length; i++) {
      const client = clients[i]
      if (!client || !client.address) continue
      const klass = String(client.class || client.initialClass || "").toLowerCase()
      const title = String(client.title || "").toLowerCase()

      let score = 0
      if (wanted !== "") {
        if (klass === wanted) score = 3
        else if (klass.indexOf(wanted) !== -1) score = 2
        else if (title.indexOf(wanted) !== -1) score = 1
      }
      if (score === 0) continue

      const order = Number(client.focusHistoryID === undefined ? 9999 : client.focusHistoryID)
      if (!best || score > best.score || (score === best.score && order < best.order)) {
        best = { address: String(client.address), score: score, order: order }
      }
    }

    if (best) {
      // Dispatched as Lua: the config manager rewrites the old
      // `focuswindow address:0x..` form before evaluating, and that is not a Lua
      // expression, so it fails. This is the form the dock uses.
      Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({window = "' + best.address + '"})'])
      return
    }

    if (pending.link !== "") Quickshell.execDetached(["xdg-open", pending.link])
  }

  property Process focusClients: Process {
    command: ["hyprctl", "clients", "-j"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: root.focusFrom(this.text)
    }

    onExited: {
      // A failed `hyprctl` still has to clear the pending click, or the next one
      // would think it already has an answer. If it produced no output at all,
      // the link is the only useful fallback left.
      const pending = root.pendingFocus
      root.pendingFocus = null
      if (pending && pending.link !== "") Quickshell.execDetached(["xdg-open", pending.link])
    }
  }

  property Timer replayTimer: Timer {
    interval: 12000
    onTriggered: root.closeReplay()
  }

  // A caller that needs a known state rather than the inverse. Focus mode uses
  // this so it can silence everything while it runs and then put back whatever
  // the user had chosen before.
  function setDnd(value) {
    const next = !!value
    if (root.doNotDisturb === next) return
    root.doNotDisturb = next
  }

  function toggle() {
    root.doNotDisturb = !root.doNotDisturb
  }

  // Silencing takes the current batch with it, so the screen matches the state
  // the indicator is showing — and a replay, being a temporary view of the past,
  // should not linger over the desktop.
  onDoNotDisturbChanged: {
    if (root._hydrating) return

    root.saveDnd()

    if (root.doNotDisturb) {
      root.closeReplay()
      root.dismissSilenced()
    }
  }

  property NotificationServer server: NotificationServer {
    // Editing the bar reloads the shell; that should not wipe what is on
    // screen or lose a notification mid-read.
    keepOnReload: true

    // What the card can actually draw, told to senders. Both default to false:
    // an application that checks the server's capabilities will not send the
    // action buttons the card renders, nor the image it would show. Markup is
    // left off because the body is drawn as plain text.
    actionsSupported: true
    imageSupported: true

    onNotification: function (notification) {
      // Silencing means "do not interrupt me", but our own feedback for
      // something the user just did, and a genuine CLI emergency, still show.
      // Everything else is written to history and left untracked, so it never
      // becomes a popup.
      const quiet = root.isQuiet(notification)

      // An app repeating itself — a polling script, a volume readout — is one
      // piece of information. Keep the newest card instead of stacking an
      // identical one under it; the older entry is archived as it is dismissed.
      // The same object is skipped: that is an in-place update, not a repeat.
      if (!quiet) {
        for (let i = root.tracked.length - 1; i >= 0; i--) {
          const existing = root.tracked[i]
          if (existing === notification) break
          if (root.sameNotification(existing, notification)) {
            existing.dismiss()
            break
          }
        }
      }

      NotificationStore.begin(notification, quiet)
      if (quiet) return

      notification.tracked = true
    }
  }

  function sweepNow() {
    const ids = []
    for (const notification of root.tracked) ids.push(notification.id)
    NotificationStore.sweep(ids)
  }

  // Nothing calls us when a notification ends: the card expires or dismisses it,
  // but the client is equally free to close its own notification, and that never
  // reaches the shell. The tracked list is what drops the entry when that
  // happens, so watching the list archives the moment it does — every insert
  // and removal, rather than polling for a gap once a second.
  //
  // Held as properties rather than declared as children: a QtObject has no
  // default property, so a bare `Connections { }` here has nowhere to go.
  property Connections trackedChanges: Connections {
    target: root.server.trackedNotifications
    function onValuesChanged() { root.sweepNow() }
  }

  // One reconciliation after startup, not a poll: the store builds its
  // id-to-file map off disk asynchronously, and after a reload the daemon
  // re-emits what it still holds. Waiting for `ready` means that read is done,
  // so anything still in `live` that is not tracked is a popup the shell did
  // not survive, and is archived now rather than left for the reaper.
  property Connections storeReady: Connections {
    target: NotificationStore
    function onReadyChanged() {
      if (NotificationStore.ready) root.sweepNow()
    }
  }
}
