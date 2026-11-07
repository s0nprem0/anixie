pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "fuzzy.js" as Fuzzy

// The shell's picker controller.
QtObject {
  id: root

  // Request identity/generation to ignore stale reads
  property int requestGen: 0
  property int activeRequestGen: 0
  property string activeRequestPath: ""

  // The request file, set by open() before it is read.
  property string requestPath: ""

  property Process requestReader: Process {
    command: [
      "sh",
      "-c",
      "p=\"$1\"; cat -- \"$p\" 2>/dev/null; rm -f -- \"$p\"",
      "read-request",
      root.requestPath
    ]

    stdout: StdioCollector {
      property int gen: root.requestGen
      onStreamFinished: {
        const text = this.text
        root.applyRequest(text, this.gen)
      }
    }
  }

  // Shown. Gates the window's visibility and its keyboard focus.
  property bool shown: false

  // Navigation stack for drill-down sub-menus. Each entry is a saved frame.
  property var navStack: []

  // "list" picks from the entries. "input" is a bare text field with no list.
  property string mode: "list"

  // Whether Enter on an empty input field counts as an answer.
  property bool allowEmpty: false

  // Draw a dimmed group line above each run of entries sharing a group.
  property bool grouped: false

  // Whether the list also takes live suggestions from the menu.
  property bool dynamic: false
  property int dynamicGen: 0

  // The menu's tab strip.
  property bool tabs: false
  property int tab: 0
  property string tabHint: ""
  readonly property int tabCount: 4

  // The suggestions live on MenuHost (refreshDynamic fills them there);
  // PickHost only reads. Keeping two copies meant the suggestions were
  // never visible: every query landed on an empty list.

  property string title: ""
  property string placeholder: ""

  property var entries: []
  property var results: []
  property int selected: 0
  property string query: ""

  // Commands to run on a choice and on a dismissal. `{}` in onSelect is replaced
  // by the chosen value.
  property string onSelect: ""
  property string onCancel: ""
  property bool executed: false

  readonly property bool isInput: root.mode === "input"
  readonly property bool hasResults: root.results.length > 0
  function getCurrent() {
    if (!root.hasResults) return null
    if (root.selected < 0 || root.selected >= root.results.length) return null
    const item = root.results[root.selected]
    if (!item) return null
    return item.row || null
  }

  readonly property var current: root.getCurrent()

  // How many rows the list shows at once.
  readonly property int maxVisible: 12

  function groupOf(index) {
    if (!root.grouped || index < 0 || index >= root.results.length) return ""

    const row = root.results[index].row
    if (!row || row.group === undefined || row.group === null) return ""

    const group = String(row.group)
    if (group === "") return ""

    if (index > 0) {
      const above = root.results[index - 1].row
      if (above && above.group !== undefined && String(above.group) === group) return ""
    }

    return group
  }

  // Take the request at `path` and show it.
  function open(path) {
    const p = String(path !== undefined && path !== null ? path : "")
    if (p === "") {
      console.warn("pick: empty request path")
      return "bad"
    }
    root.requestGen += 1
    root.requestPath = p
    root.activeRequestPath = p

    try {
      if (requestReader.running) requestReader.running = false
    } catch (e) {}
    requestReader.running = true

    return "ok"
  }

  function applyRequest(raw, gen) {
    if (gen !== undefined && gen !== null && gen !== root.requestGen) {
      return
    }
    if (!raw || raw === "") {
      console.warn("pick: no request to read at " + root.requestPath)
      return
    }

    let request
    try {
      request = JSON.parse(raw)
    } catch (error) {
      console.warn("pick: could not read the request: " + error)
      return
    }

    if (!request || typeof request !== "object") {
      console.warn("pick: invalid request")
      return
    }

    root.present(request)
  }

  function normBool(v, d) {
    if (v === undefined || v === null) return !!d
    return !!v
  }

  function normInt(v, d, min, max) {
    const n = Number(v)
    if (!isFinite(n)) return d
    let x = Math.round(n)
    if (min !== undefined && x < min) x = min
    if (max !== undefined && x > max) x = max
    return x
  }

  // Show a request that is already an object.
  function present(request) {
    if (!request || typeof request !== "object") return

    root.activeRequestGen = root.requestGen
    root.dynamicGen = root.requestGen
    root.executed = false

    root.title = String(request.title !== undefined && request.title !== null ? request.title : "")
    root.placeholder = String(request.placeholder !== undefined && request.placeholder !== null ? request.placeholder : "")
    const mode = String(request.mode !== undefined && request.mode !== null ? request.mode : "list")
    root.mode = (mode === "input") ? "input" : "list"
    root.allowEmpty = !!request.allowEmpty
    root.grouped = !!request.grouped
    root.dynamic = !!request.dynamic
    root.tabs = !!request.tabs
    const tabCount = (root.tabCount !== undefined) ? root.tabCount : 4
    root.tab = root.normInt(request.tab, 0, 0, Math.max(0, tabCount - 1))
    root.tabHint = String(request.tabHint !== undefined && request.tabHint !== null ? request.tabHint : "")
    root.onSelect = String(request.onSelect !== undefined && request.onSelect !== null ? request.onSelect : "")
    root.onCancel = String(request.onCancel !== undefined && request.onCancel !== null ? request.onCancel : "")

    if (Array.isArray(request.entries)) {
      root.entries = request.entries
    } else {
      root.entries = []
    }

    root.query = ""
    root.selected = 0

    root.dynamicTimer.stop()
    // Always drop the previous request's suggestions: with the read
    // side on MenuHost they would linger until the 180ms timer fired,
    // flashing one request's answers inside another's.
    try { MenuHost.clearDynamic() } catch (e) {}

    root.shown = true
    root.apply()
  }

  // Replace the list when the menu changes tab.
  function tabView(index, entries, dynamic, placeholder, hint) {
    root.dynamicGen = root.requestGen
    root.executed = false
    const tabCount = (root.tabCount !== undefined) ? root.tabCount : 4
    root.tab = root.normInt(index, root.tab, 0, Math.max(0, tabCount - 1))
    if (Array.isArray(entries)) {
      root.entries = entries
    } else {
      root.entries = []
    }
    root.dynamic = !!dynamic
    root.placeholder = String(placeholder !== undefined && placeholder !== null ? placeholder : root.placeholder)
    root.tabHint = String(hint !== undefined && hint !== null ? hint : root.tabHint)
    root.query = ""
    root.selected = 0
    root.dynamicTimer.stop()
    try { MenuHost.clearDynamic() } catch (e) {}
    root.apply()
  }

  // Drill-down sub-menus. A selected row carrying a `submenu` array pushes the
  // current frame onto the stack and presents the children, with a Back row on
  // top. `back()` pops, or dismisses when already at the top level.
  function pushSubmenu(children, title) {
    if (!Array.isArray(children) || children.length === 0) return
    const frame = {
      entries: root.entries,
      title: root.title,
      placeholder: root.placeholder,
      grouped: root.grouped,
      tabs: root.tabs,
      tab: root.tab,
      tabHint: root.tabHint,
      query: root.query,
      selected: root.selected,
      dynamic: root.dynamic
    }
    root.navStack = root.navStack.concat([frame])

    const backRow = { label: "← Back", group: "", header: false, separator: false, back: true }
    const withBack = [backRow].concat(children)
    root.present({
      title: title !== undefined && title !== null ? String(title) : root.title,
      placeholder: root.placeholder,
      grouped: root.grouped,
      dynamic: false,
      tabs: false,
      entries: withBack
    })
  }

  function popSubmenu() {
    if (!Array.isArray(root.navStack) || root.navStack.length === 0) {
      root.dismiss()
      return
    }
    const stack = root.navStack.slice()
    const frame = stack.pop()
    root.navStack = stack
    root.present(frame)
  }

  function back() {
    if (Array.isArray(root.navStack) && root.navStack.length > 0) root.popSubmenu()
    else root.dismiss()
  }

  // Headers and separators are drawn rows rather than choices. They carry no
  // command, so the keys must walk past them and Return over one must do
  // nothing instead of dismissing the picker.
  function selectable(row) {
    return !(row && (row.header === true || row.separator === true))
  }

  function findSelectable(from, direction) {
    let index = from
    while (index >= 0 && index < root.results.length) {
      if (root.selectable(root.results[index].row)) return index
      index += direction
    }
    return -1
  }

  function ensureSelection() {
    if (!Array.isArray(root.results) || root.results.length === 0) {
      root.selected = 0
      return
    }
    if (root.selected < 0 || root.selected >= root.results.length) {
      root.selected = 0
    }
    if (!root.results[root.selected] || !root.selectable(root.results[root.selected].row)) {
      let next = root.findSelectable(root.selected + 1, 1)
      if (next < 0) next = root.findSelectable(root.selected - 1, -1)
      if (next < 0) next = root.findSelectable(0, 1)
      root.selected = next < 0 ? 0 : next
    }
  }

  function apply() {
    if (!root.shown) return
    if (root.isInput) {
      root.results = []
      if (root.selected !== 0) root.selected = 0
      return
    }

    let entries = []
    if (Array.isArray(root.entries)) {
      entries = root.entries
    }

    let filtered = []
    try {
      filtered = Fuzzy.filter(entries, root.query || "")
    } catch (e) {
      filtered = []
    }

    const results = []

    if (root.dynamic && String(root.query || "").trim() !== "") {
      const lead = MenuHost.dynamicLead
      if (Array.isArray(lead)) {
        for (let i = 0; i < lead.length; i++) {
          if (lead[i]) results.push({ row: lead[i], score: 0, positions: [], index: -1 })
        }
      }
    }

    for (let j = 0; j < filtered.length; j++) results.push(filtered[j])

    if (root.dynamic && String(root.query || "").trim() !== "") {
      const tail = MenuHost.dynamicTail
      if (Array.isArray(tail)) {
        for (let k = 0; k < tail.length; k++) {
          if (tail[k]) results.push({ row: tail[k], score: 0, positions: [], index: -1 })
        }
      }
    }

    root.results = results

    if (!Array.isArray(root.results) || root.results.length === 0) {
      root.selected = 0
    } else if (root.selected >= root.results.length) {
      root.selected = Math.max(0, root.results.length - 1)
    }
    root.ensureSelection()
  }

  function setQuery(text) {
    if (!root.shown) return
    root.query = String(text !== undefined && text !== null ? text : "")
    root.selected = 0

    if (!root.dynamic) {
      root.apply()
      return
    }

    const q = root.query
    if (q.trim() === "") {
      root.dynamicTimer.stop()
      try { MenuHost.clearDynamic() } catch (e) {}
    } else {
      root.dynamicTimer.restart()
    }

    root.apply()
  }

  property Timer dynamicTimer: Timer {
    interval: 180
    repeat: false

    onTriggered: {
      if (!root.shown || !root.dynamic) return
      const q = String(root.query || "")
      if (q.trim() === "") return
      try {
        root.dynamicGen = root.requestGen
        MenuHost.refreshDynamic(q)
      } catch (e) {}
    }
  }

  function move(delta) {
    if (!root.shown) return
    if (!Array.isArray(root.results) || root.results.length === 0) return
    const d = Number(delta) || 0
    if (d === 0) return

    let next = root.findSelectable(root.selected + d, d > 0 ? 1 : -1)
    if (next < 0) {
      next = d > 0
        ? root.findSelectable(root.results.length - 1, -1)
        : root.findSelectable(0, 1)
    }
    if (next >= 0 && next !== root.selected) root.selected = next
  }

  // A page is a visible screen of rows rather than a tenth of the list, so a
  // jump lands somewhere you can see.
  function page(direction) {
    root.move(direction * (root.maxVisible - 1))
  }

  function first() {
    const next = root.findSelectable(0, 1)
    if (next >= 0) root.selected = next
  }

  function last() {
    const next = root.findSelectable(root.results.length - 1, -1)
    if (next >= 0) root.selected = next
  }

  function accept() {
    if (!root.shown) return
    if (root.executed) return

    const select = root.onSelect

    if (root.isInput) {
      const typed = String(root.query !== undefined && root.query !== null ? root.query : "")
      if (typed.length === 0 && !root.allowEmpty) {
        root.dismiss()
        return
      }
      root.executed = true
      root.dismiss()
      root.runTemplate(select, typed)
      return
    }

    const entry = root.getCurrent()
    if (!entry) {
      root.dismiss()
      return
    }
    if (!root.selectable(entry)) {
      root.ensureSelection()
      return
    }

    // Drill-down: a row carrying a submenu opens it instead of running.
    if (entry && Array.isArray(entry.submenu)) {
      root.pushSubmenu(entry.submenu, entry.label !== undefined && entry.label !== null ? String(entry.label) : "")
      return
    }
    if (entry && entry.back === true) {
      root.popSubmenu()
      return
    }

    const value = String(entry.value !== undefined && entry.value !== null ? entry.value : (entry.label !== undefined && entry.label !== null ? entry.label : ""))

    const own = String(entry.run !== undefined && entry.run !== null ? entry.run : "")
    const app = entry.app

    root.executed = true
    root.dismiss()
    if (app) {
      try { MenuHost.launch(app) } catch (e) {}
    } else if (own.length > 0) {
      try { Commands.run(own) } catch (e) {}
    } else {
      root.runTemplate(select, value)
    }
  }

  function dismiss() {
    if (!root.shown && root.executed) {
      const cancel = root.onCancel
      root.onSelect = ""
      root.onCancel = ""
      if (cancel && cancel.length > 0) {
        try { Commands.run(cancel) } catch (e) {}
      }
      return
    }
    if (!root.shown) return

    const cancel = root.onCancel

    root.dynamicTimer.stop()
    if (root.dynamic) {
      try { MenuHost.clearDynamic() } catch (e) {}
    }

    root.shown = false
    root.onSelect = ""
    root.onCancel = ""

    if (!root.executed && cancel && cancel.length > 0) {
      try { Commands.run(cancel) } catch (e) {}
    }
  }

  // Splice a value into a command template, quoting it here rather than leaving
  // it to the caller.
  function runTemplate(template, value) {
    if (root.executed) return
    const line = String(template !== undefined && template !== null ? template : "")
    if (line.length === 0) return
    const v = value !== undefined && value !== null ? value : ""
    try {
      Commands.run(line.split("{}").join(Util.shellQuote(v)))
    } catch (e) {}
  }
}