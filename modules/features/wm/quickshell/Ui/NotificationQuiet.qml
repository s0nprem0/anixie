import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "NotificationText.js" as NotificationText

// Silence: the explicit DND switch, per-sender snoozes, the preferences that
// live beside them, and the rules that decide whether an arriving notification
// may interrupt. The daemon owns the server and the live stack; this only
// answers questions about them and persists its own state.
QtObject {
  id: quiet

  property var host: null

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
      text = String(quiet.dndFile.text()).trim()
    } catch (e) {
      // No file yet: the first run starts unsilenced.
    }
    if (text === "") return

    quiet._hydrating = true
    quiet.doNotDisturb = text === "on" || text === "true" || text === "1"
    quiet._hydrating = false
  }

  // Written through a process and a file adapter, the same way the bar's layout
  // is saved: the directory is made first, because a write into a directory that
  // does not exist yet is a drop that silently does nothing.
  function saveDnd() {
    quiet._pendingDnd = quiet.doNotDisturb ? "on\n" : "off\n"
    quiet.dndMkdir.running = false
    quiet.dndMkdir.running = true
  }

  property FileView dndFile: FileView {
    path: Qt.resolvedUrl(quiet.dndPath)
    printErrors: false
    blockLoading: true
    atomicWrites: true

    Component.onCompleted: quiet.loadDnd()
  }

  property Process dndMkdir: Process {
    command: ["mkdir", "-p", NotificationStore.stateDir]
    running: false

    onExited: {
      if (quiet._pendingDnd === "") return
      quiet.dndFile.setText(quiet._pendingDnd)
      quiet._pendingDnd = ""
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

  // Preferences live beside the quiet state: the panel can change them and the
  // shell reads the same values for its window loop. The build-time value is
  // only the initial default.
  readonly property string defaultDisplayMode: "@NOTIFICATIONS_DISPLAY@"
  property string displayMode: defaultDisplayMode
  property string displayName: ""
  property bool fullscreenStepAside: true
  property int historyHours: 24

  readonly property string snoozesPath: NotificationStore.stateDir + "/snoozes.json"
  property bool _hydratingSnoozes: false
  property string _pendingSnoozes: ""

  function sourceOf(notification) {
    return NotificationText.sourceKey(notification)
  }

  function loadSnoozes() {
    let text = ""
    try {
      text = String(quiet.snoozesFile.text()).trim()
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

    quiet._hydratingSnoozes = true
    const now = Date.now() / 1000
    const globalUntil = Number(parsed.globalUntil || 0)
    quiet.globalSnoozeUntil = globalUntil > now ? globalUntil : 0
    const sources = parsed.sources && typeof parsed.sources === "object" ? parsed.sources : {}
    const next = {}
    for (const key in sources) {
      const until = Number(sources[key] || 0)
      if (until > now) next[String(key)] = until
    }
    quiet.snoozes = next
    quiet.codesBypassQuiet = parsed.codesBypassQuiet !== false
    quiet.offerSnoozeWhenSharing = parsed.offerSnoozeWhenSharing !== false
    quiet.displayMode = parsed.displayMode === "all" || parsed.displayMode === "specific"
      ? parsed.displayMode : quiet.defaultDisplayMode
    quiet.displayName = String(parsed.displayName || "")
    quiet.fullscreenStepAside = parsed.fullscreenStepAside !== false
    quiet.historyHours = Number(parsed.historyHours || 24)
    NotificationStore.historyHours = quiet.historyHours
    quiet._hydratingSnoozes = false
  }

  function saveSnoozes() {
    quiet._pendingSnoozes = JSON.stringify({
      globalUntil: quiet.globalSnoozeUntil,
      sources: quiet.snoozes,
      codesBypassQuiet: quiet.codesBypassQuiet,
      offerSnoozeWhenSharing: quiet.offerSnoozeWhenSharing,
      displayMode: quiet.displayMode,
      displayName: quiet.displayName,
      fullscreenStepAside: quiet.fullscreenStepAside,
      historyHours: quiet.historyHours
    }) + "\n"
    quiet.snoozesMkdir.running = false
    quiet.snoozesMkdir.running = true
  }

  property FileView snoozesFile: FileView {
    path: Qt.resolvedUrl(quiet.snoozesPath)
    printErrors: false
    blockLoading: true
    atomicWrites: true

    Component.onCompleted: quiet.loadSnoozes()
  }

  property Process snoozesMkdir: Process {
    command: ["mkdir", "-p", NotificationStore.stateDir]
    running: false

    onExited: {
      if (quiet._pendingSnoozes === "") return
      quiet.snoozesFile.setText(quiet._pendingSnoozes)
      quiet._pendingSnoozes = ""
    }
  }

  // Trims expired entries without asking the user to do anything. The file is
  // rewritten only when something actually went away.
  readonly property bool hasSnoozes: {
    const now = Date.now() / 1000
    if (quiet.globalSnoozeUntil > now) return true
    for (const key in quiet.snoozes) if (Number(quiet.snoozes[key] || 0) > now) return true
    return false
  }

  property Timer snoozeTicker: Timer {
    interval: 30000
    repeat: true
    running: quiet.hasSnoozes
    onTriggered: quiet.pruneSnoozes()
  }

  function pruneSnoozes() {
    const now = Date.now() / 1000
    const next = {}
    let changed = quiet.globalSnoozeUntil > 0 && quiet.globalSnoozeUntil <= now
    if (changed) quiet.globalSnoozeUntil = 0
    for (const key in quiet.snoozes) {
      if (Number(quiet.snoozes[key] || 0) > now) next[key] = quiet.snoozes[key]
      else changed = true
    }
    if (!changed) return
    quiet.snoozes = next
    quiet.saveSnoozes()
  }

  function snoozeOptions() {
    return [
      { label: "For 15 minutes", seconds: 15 * 60 },
      { label: "For 1 hour", seconds: 60 * 60 },
      { label: "Until tomorrow 8am", seconds: quiet.untilTomorrow() }
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
    for (const key in quiet.snoozes) {
      if (Number(quiet.snoozes[key] || 0) > now) next[key] = quiet.snoozes[key]
    }

    if (source === "*") quiet.globalSnoozeUntil = until
    else if (source !== "") next[String(source).toLowerCase()] = until

    quiet.snoozes = next
    quiet.saveSnoozes()
    quiet.dismissSource(source)
    quiet.host.closeReplay()
  }

  function unsnooze(source) {
    if (source === "*") {
      quiet.globalSnoozeUntil = 0
    } else {
      const next = {}
      for (const key in quiet.snoozes) if (key !== source) next[key] = quiet.snoozes[key]
      quiet.snoozes = next
    }
    quiet.saveSnoozes()
  }

  function dismissSource(source) {
    const wanted = String(source || "").toLowerCase()
    for (let i = quiet.host.tracked.length - 1; i >= 0; i--) {
      const item = quiet.host.tracked[i]
      if (wanted === "*" || quiet.sourceOf(item) === wanted) item.dismiss()
    }
  }

  function quietSources() {
    const now = Date.now() / 1000
    const out = []
    if (quiet.globalSnoozeUntil > now) out.push({ key: "*", label: "Everything", until: quiet.globalSnoozeUntil })
    for (const key in quiet.snoozes) {
      const until = Number(quiet.snoozes[key] || 0)
      if (until > now) out.push({ key: key, label: key, until: until })
    }
    return out
  }

  property bool codesBypassQuiet: true
  property bool offerSnoozeWhenSharing: true

  function setCodesBypass(value) {
    quiet.codesBypassQuiet = !!value
    quiet.saveSnoozes()
  }

  function setDisplayMode(value) {
    const mode = String(value || "")
    if (mode !== "focused" && mode !== "all" && mode !== "specific") return
    quiet.displayMode = mode
    quiet.saveSnoozes()
  }

  function setDisplayName(value) {
    quiet.displayName = String(value || "")
    quiet.saveSnoozes()
  }

  function setFullscreenStepAside(value) {
    quiet.fullscreenStepAside = !!value
    quiet.saveSnoozes()
  }

  function setOfferSnoozeWhenSharing(value) {
    quiet.offerSnoozeWhenSharing = !!value
    quiet.saveSnoozes()
  }

  function setHistoryHours(value) {
    const hours = Number(value)
    if (!isFinite(hours) || hours <= 0) return
    quiet.historyHours = hours
    NotificationStore.historyHours = hours
    quiet.saveSnoozes()
    NotificationStore.refresh()
  }

  function codeBypass(notification) {
    if (!quiet.codesBypassQuiet || !notification) return false
    const text = String(notification.summary || "").slice(0, 2048)
      + "\n" + String(notification.body || "").slice(0, 32768)
    return NotificationText.code(text) !== ""
  }

  function quietReason(notification) {
    if (quiet.bypassesSilencing(notification)) return ""
    if (quiet.codeBypass(notification)) return ""
    const now = Date.now() / 1000
    if (quiet.doNotDisturb) return "silenced"
    if (quiet.globalSnoozeUntil > now) return "snoozed"
    if (Number(quiet.snoozes[quiet.sourceOf(notification)] || 0) > now) return "snoozed"
    return ""
  }

  function isQuiet(notification) {
    return quiet.quietReason(notification) !== ""
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

    if (quiet.ownApps.indexOf(app) !== -1) return true
    return app === "notify-send" && notification.urgency === NotificationUrgency.Critical
  }

  // What silencing may take with it: everything except the messages that are
  // allowed through it. Turning DND on must not throw away the critical alert
  // that was meant to survive it.
  function dismissSilenced() {
    for (let i = quiet.host.tracked.length - 1; i >= 0; i--) {
      const item = quiet.host.tracked[i]
      if (!quiet.bypassesSilencing(item) && !quiet.codeBypass(item)) item.dismiss()
    }
  }

  // A caller that needs a known state rather than the inverse. Focus mode uses
  // this so it can silence everything while it runs and then put back whatever
  // the user had chosen before.
  function setDnd(value) {
    const next = !!value
    if (quiet.doNotDisturb === next) return
    quiet.doNotDisturb = next
  }

  function toggle() {
    quiet.doNotDisturb = !quiet.doNotDisturb
  }

  // Silencing takes the current batch with it, so the screen matches the state
  // the indicator is showing — and a replay, being a temporary view of the past,
  // should not linger over the desktop.
  onDoNotDisturbChanged: {
    if (quiet._hydrating) return

    if (quiet.doNotDisturb && quiet.host.sharingActive) quiet.host.noteSharingSnoozed()
    quiet.saveDnd()

    if (quiet.doNotDisturb) {
      quiet.host.closeReplay()
      quiet.host.closeRestored()
      quiet.dismissSilenced()
    }
  }
}
