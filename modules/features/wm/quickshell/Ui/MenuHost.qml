pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "Jsonc.js" as Jsonc
import "Suggest.js" as Suggest

// The menu: every command this shell has, flattened and searchable, with the
// applications alongside them — built here, in the shell, rather than by a
// script that hands the shell a finished list.
//
// It used to be a script. A keypress ran `menu`, which ran `menu-tree`, which
// flattened menu.json with jq, ran a process for every `when` and `state`, asked
// Nix for the profile's closure to find the desktop entries, handed the rows to
// jq again, and sent the result in through `quickshell ipc` — itself a Qt process
// starting up just to deliver one message. About half a second warm, and nearer
// two after a rebuild. None of that was work: every answer it went out to fetch
// was already sitting in the shell.
//
//   - the applications are Quickshell's DesktopEntries, which walks
//     XDG_DATA_DIRS once and watches it. The closure farm the script built was
//     there because NixOS was said to keep desktop entries off that path; it
//     does not — the user and system profiles are both on it — and what the farm
//     found beyond it was what the closure dragged in rather than what was
//     installed: GTK demos, goa-daemon, a second file manager;
//   - the toggles' states are IndicatorHost's and NotificationHost's, which the
//     `toggle` command already pushes to;
//   - whether a recording is running is RecorderHost's;
//   - the themes are Theme's own palette list.
//
// So the key is a Hyprland global shortcut, caught in shell.qml, and opening the
// menu is a function call: no process between the keypress and the picker.
//
// The tree is menu.json. A group's name is a prefix on its entries' path rather
// than a place to navigate to, so the whole tree is searched at once and `only`
// is the same menu with a filter rather than a second list kept in step by hand.
// An entry's `list`, `state` and `when` name one of the sources below rather
// than a command, because the answer is here and asking a process for it is what
// this replaced.
//
// The root of the menu is also the launcher, so it carries the reference's
// shape: tabs for all/apps/web/files, a "most used" section built from launches
// this shell counted, two columns for an application's name and command, and the
// compositor's open windows above them as live thumbnails. The tabs are filters
// on the same list — "all" is the menu that was here before — rather than four
// separate surfaces to keep in step.
QtObject {
  id: root

  // What a terminal application is run in.
  readonly property string terminal: "kitty"

  // Read once: the config is a store path, so the tree changes with a rebuild,
  // and a rebuild restarts the shell.
  property var tree: null

  property FileView treeFile: FileView {
    path: Quickshell.shellPath("menu.json")
    blockLoading: true
    onLoaded: root.tree = root.parseTree()
  }

  function parseTree() {
    try {
      return JSON.parse(root.treeFile.text())
    } catch (error) {
      console.warn("menu: could not read menu.json: " + error)
      return { entries: [] }
    }
  }

  // The user's own entries, merged over the shipped tree whenever the menu is
  // opened. This is the one menu file meant to be edited, so it is writable
  // under ~/.config rather than in the store, and it is JSONC so a comment or a
  // trailing comma costs nothing.
  readonly property string extensionPath: (Quickshell.env("XDG_CONFIG_HOME")
    || Quickshell.env("HOME") + "/.config") + "/anixie/menu.json"

  property var extension: ({ entries: [] })

  property FileView extensionFile: FileView {
    path: Qt.resolvedUrl(root.extensionPath)
    printErrors: false
    blockLoading: true
    blockAllReads: true
    watchChanges: true
    onFileChanged: root.reloadExtension()
  }

  function parseExtension(text) {
    const raw = String(text || "").trim()
    if (raw === "") return { entries: [] }

    try {
      const parsed = Jsonc.parse(raw)
      if (parsed && Array.isArray(parsed.entries)) return parsed
      console.warn("menu: the extension needs an entries array")
    } catch (error) {
      console.warn("menu: could not read the extension: " + error)
    }

    return { entries: [] }
  }

  // Read fresh on each open rather than trusting a change notification: editing
  // the file and pressing the key should show the edit, and the file is small
  // enough that the blocking read is cheaper than a process to cat it.
  function reloadExtension() {
    try {
      root.extensionFile.reload()
      root.extension = root.parseExtension(root.extensionFile.text())
    } catch (error) {
      root.extension = { entries: [] }
    }
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value))
  }

  // Merge the user's entries over the shipped ones, by group name for a group
  // and by label within its group for a leaf. A user entry with the same
  // identity replaces the shipped one; a new one is appended. `"hidden": true`
  // removes the shipped entry instead, which is the only way to take something
  // off the menu without a rebuild.
  function mergeEntries(base, extra) {
    const out = (base || []).map(function (entry) { return root.clone(entry) })
    const items = Array.isArray(extra) ? extra : []

    for (const item of items) {
      if (!item || typeof item !== "object") continue

      const isGroup = item.group !== undefined && Array.isArray(item.entries)
      const key = isGroup ? "group" : "label"
      const value = String(item[key] || "")

      let found = -1
      if (value !== "") {
        for (let i = 0; i < out.length; i++) {
          const candidate = out[i]
          const candidateIsGroup = candidate && candidate.group !== undefined
            && Array.isArray(candidate.entries)
          if (candidateIsGroup === isGroup && String(candidate[key] || "") === value) {
            found = i
            break
          }
        }
      }

      if (item.hidden === true) {
        if (found >= 0) out.splice(found, 1)
        continue
      }

      if (isGroup) {
        if (found >= 0) out[found].entries = root.mergeEntries(out[found].entries, item.entries)
        else out.push(root.clone(item))
        continue
      }

      if (found >= 0) out[found] = root.clone(item)
      else out.push(root.clone(item))
    }

    return out
  }

  function entries() {
    const shipped = root.tree && Array.isArray(root.tree.entries) ? root.tree.entries : []
    const extra = root.extension && Array.isArray(root.extension.entries) ? root.extension.entries : []
    return root.mergeEntries(shipped, extra)
  }

  // The applications, sorted and deduplicated by name once per change to the
  // installed set rather than once per open. Two desktop entries can carry the
  // same Name, and the menu cannot tell those apart; the first one wins.
  readonly property var apps: {
    const all = DesktopEntries.applications.values.filter(function (entry) {
      return !entry.noDisplay && entry.name !== ""
    })
    all.sort(function (a, b) {
      return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
    })

    const seen = {}
    return all.filter(function (entry) {
      if (seen[entry.name]) return false
      seen[entry.name] = true
      return true
    })
  }

  // Called once at startup, from shell.qml. DesktopEntries does not scan until it
  // is first asked, and the scan takes a second or two, so a menu that asked on
  // its first open would open with no applications in it.
  function warm() {
    root.reloadExtension()
    root.reloadUsage()
    if (!root.tree) root.tree = root.parseTree()
    return root.apps.length
  }

  // ---- the tab strip ----
  //
  // The menu's root is the launcher: all, apps, web, files. "all" is the menu
  // that was here before the tabs, and stays the default so a command or a theme
  // is still one query away rather than one tab away. "apps" is the reference's
  // app launcher; web and files are the two dynamic searches the menu already
  // knew how to do, now reachable without knowing the old punctuation.
  readonly property var tabNames: ["all", "apps", "web", "files"]
  property int tab: 0

  // What each tab says while it is empty. The web and files tabs have no list
  // until something is typed, so this is what the space is for.
  readonly property var tabMeta: [
    { placeholder: "Search apps, commands and files…", hint: "Type to search applications" },
    { placeholder: "Search applications…", hint: "Type to search applications" },
    { placeholder: "Search the web…", hint: "Type to search the web" },
    { placeholder: "Search files…", hint: "Type to search files" }
  ]

  function selectTab(index) {
    const tab = Math.max(0, Math.min(root.tabNames.length - 1, Number(index)))
    const meta = root.tabMeta[tab]

    root.tab = tab
    root.clearDynamic()
    PickHost.tabView(tab, root.tabEntries(tab), tab !== 1, meta.placeholder, meta.hint)
  }

  // ---- most used ----
  //
  // One entry per desktop id, counting launches rather than opens. The file is
  // small and only this file writes it; the empty answer is a plain object so
  // the sort below does not need a second path.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/anixie"
  readonly property string usagePath: root.stateDir + "/app-usage.json"

  property var usage: ({})
  property bool usageDirty: false

  // One write for a burst of launches rather than one process each: two
  // commands racing to replace the same file would leave it holding whichever
  // finished last, which is not necessarily the newest state.
  property Timer usageWrite: Timer {
    interval: 200
    onTriggered: root.flushUsage()
  }

  function flushUsage() {
    if (!root.usageDirty) return
    root.usageDirty = false

    // Written through the shell rather than a FileView: the directory may not
    // exist on a fresh account, and one command can make it and write in the
    // same breath. The contents are this shell's own ids and numbers, so the
    // quoting is belt and braces rather than a need.
    Commands.run("mkdir -p " + Util.shellQuote(root.stateDir)
      + " && printf '%s' " + Util.shellQuote(JSON.stringify(root.usage))
      + " > " + Util.shellQuote(root.usagePath))
  }

  property FileView usageFile: FileView {
    path: Qt.resolvedUrl(root.usagePath)
    printErrors: false
    blockLoading: true
    blockAllReads: true
    onLoaded: root.usage = root.parseUsage(root.usageFile.text())
  }

  function parseUsage(text) {
    const raw = String(text || "").trim()
    if (raw === "") return {}

    try {
      const parsed = JSON.parse(raw)
      return parsed && typeof parsed === "object" ? parsed : {}
    } catch (error) {
      console.warn("menu: could not read the usage file: " + error)
      return {}
    }
  }

  function reloadUsage() {
    try {
      root.usageFile.reload()
      root.usage = root.parseUsage(root.usageFile.text())
    } catch (error) {
      root.usage = {}
    }
  }

  function recordLaunch(entry) {
    if (!entry || entry.id === "") return

    const next = root.clone(root.usage)
    const previous = next[entry.id] || { count: 0, last: 0 }
    next[entry.id] = {
      count: Number(previous.count || 0) + 1,
      last: Date.now()
    }
    root.usage = next
    root.usageDirty = true
    root.usageWrite.restart()
  }

  // The most-launched applications that are still installed. Reading the ids
  // back through DesktopEntries drops an entry that has been uninstalled rather
  // than leaving a row that cannot launch anything.
  function usageRows() {
    const rows = []
    for (const id in root.usage) {
      const entry = DesktopEntries.byId(id)
      const data = root.usage[id] || {}
      if (!entry || entry.noDisplay || entry.name === "") continue
      rows.push({ entry: entry, count: Number(data.count || 0), last: Number(data.last || 0) })
    }

    rows.sort(function (a, b) {
      if (a.count !== b.count) return b.count - a.count
      if (a.last !== b.last) return b.last - a.last
      return a.entry.name.localeCompare(b.entry.name, undefined, { sensitivity: "base" })
    })

    return rows.slice(0, 5).map(function (item) {
      return root.appRow(item.entry)
    })
  }

  function appRow(entry) {
    return {
      label: entry.name,
      group: "",
      icon: entry.icon,
      detail: String(entry.execString || ""),
      match: root.appMatch(entry),
      app: entry
    }
  }

  function appRows() {
    return root.apps.map(function (entry) { return root.appRow(entry) })
  }

  // The rows one tab shows. Web and files start empty because their rows are
  // made from the query; the other two begin with the usage section, then the
  // full list — the reference repeats the most-used entries below the heading
  // rather than removing them from where they would be found anyway.
  function tabEntries(tab) {
    if (tab === 2 || tab === 3) return []

    const body = tab === 1 ? root.appRows() : root.rows()
    const used = root.usageRows()
    if (used.length === 0) return body

    return [{ label: "most used", header: true }]
      .concat(used)
      .concat(body)
  }

  // The live windows above the tabs, as the reference shows them when the query
  // is empty. ToplevelManager is the compositor's own list, so a window that
  // opened or closed while the menu was up is not a stale row.
  readonly property var windows: ToplevelManager.toplevels.values || []

  // Words an application can be found by that are not in its name: "browser"
  // for Firefox, "editor" for an app called Helix. Kept off the row itself —
  // the label stays the name — but carried into the matcher as a fallback.
  function appMatch(entry) {
    const parts = []
    if (entry.genericName) parts.push(String(entry.genericName))
    const words = entry.keywords || []
    for (let i = 0; i < words.length; i++) parts.push(String(words[i]))
    return parts.join(" ")
  }

  // A `list` source's children, as { label, icon, app, match }.
  function listOf(source) {
    switch (source) {
    case "apps":
      return root.appRows()
    case "themes":
      return Theme.names().map(function (name) {
        return {
          label: name,
          icon: "",
          app: null,
          state: name === Theme.name ? "current" : ""
        }
      })
    case "bar-modules":
      return BarConfig.availableModules.map(function (id) {
        return { label: String(id), icon: "", app: null }
      })
    case "bar-enabled":
      return BarConfig.enabledModules.map(function (id) {
        return { label: String(id), icon: "", app: null }
      })
    }
    console.warn("menu: no list called \"" + source + "\"")
    return []
  }

  // A `state` source's reading, as the toggle command prints it.
  function stateOf(source) {
    switch (source) {
    case "nightlight": return IndicatorHost.nightlight ? "on" : "off"
    case "idle": return IndicatorHost.idleStopped ? "off" : "on"
    case "dnd": return NotificationHost.doNotDisturb ? "on" : "off"
    case "bar-position-top": return BarContext.position === "top" ? "current" : ""
    case "bar-position-bottom": return BarContext.position === "bottom" ? "current" : ""
    case "bar-position-left": return BarContext.position === "left" ? "current" : ""
    case "bar-position-right": return BarContext.position === "right" ? "current" : ""
    case "bar-background-opaque":
      return String(BarConfig.config.background || "clear") === "opaque" ? "current" : ""
    case "bar-background-glassy":
      return String(BarConfig.config.background || "clear") === "glassy" ? "current" : ""
    case "bar-background-clear":
      return String(BarConfig.config.background || "clear") === "clear" ? "current" : ""
    case "bar-clock-format-friday":
      return String(BarConfig.settingOf("bar.clock", "format") || "dddd HH:mm") === "dddd HH:mm" ? "current" : ""
    case "bar-clock-format-date":
      return String(BarConfig.settingOf("bar.clock", "format") || "dddd HH:mm") === "ddd dd MMM  HH:mm" ? "current" : ""
    case "bar-clock-format-time":
      return String(BarConfig.settingOf("bar.clock", "format") || "dddd HH:mm") === "HH:mm" ? "current" : ""
    }
    console.warn("menu: no state called \"" + source + "\"")
    return ""
  }

  // Whether a `when` source holds. A row that only makes sense some of the time
  // — "Stop screen recording" — is left out the rest of it.
  function holds(source) {
    // A panel entry only works while its widget is on the bar: the panel is
    // anchored to that widget and PanelRegistry is what the toggle looks up.
    // On a minimal bar the widget may not be there, so hide the row rather
    // than leave one that logs a warning and does nothing.
    if (String(source).indexOf("panel:") === 0)
      return PanelRegistry.names().indexOf(String(source).slice(6)) >= 0

    switch (source) {
    case "recording": return RecorderHost.recording
    }
    console.warn("menu: no condition called \"" + source + "\"")
    return false
  }

  // Every row, in tree order. Built on each open rather than kept, because the
  // states and the `when` guards are read at that moment; it is eighty-odd small
  // objects and costs well under a millisecond.
  //
  // First wins on group and label together, so a source that returns something
  // twice does not put a second copy in the list, while two groups may each have
  // an entry of the same name.
  function rows() {
    const out = []
    const seen = {}

    function add(row) {
      const key = row.group + " › " + row.label
      if (seen[key]) return
      seen[key] = true
      out.push(row)
    }

    function walk(entries, prefix) {
      for (let i = 0; i < entries.length; i++) {
        const node = entries[i]

        if (!node || node.hidden === true) continue

        if (node.group !== undefined) {
          walk(node.entries || [], prefix.concat([node.group]))
          continue
        }

        if (node.when !== undefined && !root.holds(node.when)) continue

        const group = prefix.join(" › ")

        if (node.list !== undefined) {
          // A provider's children are grouped under the provider's own label,
          // since the provider is a leaf with a list rather than a group.
          const childGroup = prefix.concat([node.label]).join(" › ")
          const template = String(node.run || "")
          const children = root.listOf(node.list)
          for (let j = 0; j < children.length; j++) {
            const child = children[j]
            add({
              label: child.label,
              group: childGroup,
              icon: child.icon,
              state: child.state !== undefined ? String(child.state) : "",
              detail: child.detail !== undefined ? String(child.detail) : "",
              match: child.match !== undefined ? String(child.match) : "",
              app: child.app,
              run: template.split("{}").join(Util.shellQuote(child.label))
            })
          }
          continue
        }

        if (node.app !== undefined) {
          const entry = DesktopEntries.byId(node.app)
          if (!entry) continue
          // The entry's own icon rather than the blank the command rows carry:
          // this row is one application under a name of its own ("Browser"), and
          // without its icon it sits in a list of icons looking unfinished.
          add({
            label: node.label,
            group: group,
            icon: entry.icon,
            detail: String(entry.execString || ""),
            match: root.appMatch(entry),
            app: entry,
            run: ""
          })
          continue
        }

        if (!node.run) continue

        add({
          label: node.label,
          group: group,
          icon: "",
          state: node.state !== undefined ? root.stateOf(node.state) : "",
          app: null,
          run: String(node.run)
        })
      }
    }

    if (!root.tree) root.tree = root.parseTree()
    walk(root.entries(), [])
    return out
  }

  // The rows under one group, or all of them. Prefix, not substring: `Style`
  // must not pick up an entry that merely mentions Style in its group.
  function shown(only) {
    const all = root.rows()
    if (!only) return all
    return all.filter(function (row) {
      return row.group === only || row.group.indexOf(only + " › ") === 0
    })
  }

  function open(only) {
    root.reloadExtension()

    const group = String(only || "")
    const entries = group === "" ? root.tabEntries(0) : root.shown(group)
    if (entries.length === 0) {
      console.warn("menu: nothing to show" + (group ? " under \"" + group + "\"" : ""))
      return
    }

    root.clearDynamic()
    root.tab = 0

    PickHost.present({
      // The full menu opens on a search prompt rather than a redundant "menu"
      // heading; a group's own name stays as the title because that is what the
      // filtered list is.
      title: group,
      placeholder: group !== "" ? "Type to filter…" : root.tabMeta[0].placeholder,
      grouped: true,
      dynamic: group === "",
      tabs: group === "",
      tab: 0,
      tabHint: group === "" ? root.tabMeta[0].hint : "",
      entries: entries
    })
  }

  // The same rows as text, with the path the picker draws and the state in
  // parentheses: what a test can read without a picker on screen.
  function list(only) {
    return root.shown(String(only || "")).map(function (row) {
      let line = row.group !== "" ? row.group + " › " + row.label : row.label
      if (row.state !== "") line += " (" + row.state + ")"
      return line
    }).join("\n")
  }

  // ---------------------------------------------------------------- dynamic
  //
  // A query can be more than a filter on the installed entries. Arithmetic,
  // URLs, files and a web search are answered in that order: the first two sit
  // above the entries because they are unambiguous, the file hits and the web
  // search below them because the entries are still usually what was meant.
  //
  // The file search is asynchronous: fd walks the home directory, so the quick
  // answers appear immediately and the paths join the list when fd exits. A
  // query that changed in the meantime is ignored instead of overwriting the
  // new query's results with the old ones.

  property var dynamicLead: []
  property var dynamicTail: []

  readonly property string home: Quickshell.env("HOME") || ""

  // The query the running fd process was started for. Different from
  // dynamicQuery when the user has typed since; the result is then stale.
  property string fileQuery: ""

  function clearDynamic() {
    root.dynamicLead = []
    root.dynamicTail = []
    root.fileQuery = ""
    if (root.fileSearch.running) root.fileSearch.running = false
  }

  function quickRows(query) {
    const q = String(query || "")
    const lead = []
    const tail = []

    // The tab is the filter: the calculator belongs to the full menu, the two
    // web answers to the full menu and the web tab, and the files tab gets only
    // files. A URL is not a file and a sum is not a web search.
    const calc = root.tab === 0 ? Suggest.calculator(q) : null
    if (calc) {
      lead.push({
        label: "= " + calc.text,
        group: "Calculator",
        icon: "",
        state: "copy",
        match: q,
        run: "printf '%s' " + Util.shellQuote(calc.text) + " | wl-copy"
      })
    }

    const url = root.tab === 0 || root.tab === 2 ? Suggest.urlFor(q) : null
    if (url) {
      lead.push({
        label: "Open " + url,
        group: "Web",
        icon: "",
        state: "",
        match: q,
        run: "xdg-open " + Util.shellQuote(url)
      })
    } else if (q.trim() !== "" && (root.tab === 0 || root.tab === 2)) {
      // Last among the suggestions: an app called "notes" should come before a
      // web search for "notes", but a query with no app match should still
      // have somewhere to go.
      tail.push({
        label: "Search the web for “" + q.trim() + "”",
        group: "Web",
        icon: "",
        state: "",
        match: q,
        run: "xdg-open " + Util.shellQuote(Suggest.webUrl(q))
      })
    }

    return { lead: lead, tail: tail }
  }

  function refreshDynamic(query) {
    const q = String(query || "")
    const quick = root.quickRows(q)

    root.dynamicLead = quick.lead
    root.dynamicTail = quick.tail

    const wantsFiles = root.tab === 0 || root.tab === 3
    if (!wantsFiles || q.trim() === "" || !Suggest.shouldSearchFiles(q)) {
      if (root.fileSearch.running) root.fileSearch.running = false
      root.fileQuery = ""
      return
    }

    root.fileQuery = q
    root.fileSearch.command = [
      "sh",
      "-c",
      // fd is in the desktop's package set. The exclude list keeps the search
      // out of the two places a launcher never wants: VCS metadata and caches.
      // `--` stops a query beginning with `-` from reading as an option.
      "[ -n \"$1\" ] || exit 0\n" +
      "command -v fd >/dev/null 2>&1 || exit 0\n" +
      // The query echoed as the first line, so a result from a search that was
      // replaced while it ran cannot be mistaken for the current one.
      "printf '%s\\n' \"$1\"\n" +
      "exec fd --color never --hidden --max-results 20\n" +
      "  --exclude .git --exclude node_modules --exclude .cache --exclude .direnv\n" +
      "  --exclude .local/state --exclude .local/share/Trash\n" +
      "  -- \"$1\" \"$2\"",
      "file-search",
      Suggest.fileTerm(q),
      root.home
    ]

    // Restarted rather than merely started: after the first search `running`
    // stays true for a moment while the process exits, and the next keystroke
    // has to replace it, not be ignored.
    root.fileSearch.running = false
    root.fileSearch.running = true
  }

  function applyFiles(text) {
    const lines = String(text || "").split("\n")
    if (lines.length === 0) return

    // The first line is the query the search ran for. The user has typed since
    // if it is no longer the current one, and these paths answer a question
    // that is no longer on screen.
    const answered = lines.shift()
    if (answered !== root.fileQuery) return

    const files = []

    for (let i = 0; i < lines.length; i++) {
      const path = lines[i]
      if (path === "") continue

      const slash = path.lastIndexOf("/")
      files.push({
        label: slash >= 0 ? path.slice(slash + 1) : path,
        group: "Files",
        icon: "",
        state: "",
        match: path,
        run: "xdg-open " + Util.shellQuote(path)
      })
    }

    files.sort(function (a, b) {
      return a.label.localeCompare(b.label, undefined, { sensitivity: "base" })
    })

    // The web search row keeps the last place it had in quickRows.
    const quick = root.quickRows(root.fileQuery)
    root.dynamicTail = files.concat(quick.tail)
  }

  // Held as a property: a QtObject has no default property, so a bare child
  // declaration would never attach (the same reason BarConfig does this).
  property Process fileSearch: Process {
    command: ["true"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: root.applyFiles(this.text)
    }
  }

  // Run a desktop entry. Detached, so an application outlives a shell restart
  // rather than being taken down with it, and from the entry's own working
  // directory, which `command` alone does not carry. `app-launch` puts it in
  // its own systemd scope under UWSM; without it the process would stay in the
  // compositor's cgroup.
  function launch(entry) {
    if (!entry) return
    root.recordLaunch(entry)
    const command = entry.runInTerminal
      ? [root.terminal, "-e"].concat(entry.command)
      : entry.command
    Quickshell.execDetached({
      command: ["app-launch"].concat(command),
      workingDirectory: entry.workingDirectory
    })
  }

  // Launch an application by name, so the launcher can be scripted: `menu btop++`.
  // Matched on the entry's Name, which is what the menu shows, and falling back to
  // the desktop id and then Quickshell's own guess, so `menu firefox` works too.
  function launchByName(name) {
    const want = String(name)
    const lower = want.toLowerCase()
    let entry = null
    for (let i = 0; i < root.apps.length && !entry; i++) {
      if (root.apps[i].name.toLowerCase() === lower) entry = root.apps[i]
    }
    if (!entry) entry = DesktopEntries.byId(want)
    if (!entry) entry = DesktopEntries.heuristicLookup(want)
    if (!entry) return "no application called \"" + want + "\""

    root.launch(entry)
    return "ok"
  }
}
