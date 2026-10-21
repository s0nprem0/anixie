pragma Singleton

import QtQuick
import Quickshell.Io
import "fuzzy.js" as Fuzzy

// The shell's picker: a searchable list, and the one way this shell asks the
// user to choose something.
//
// It replaced fuzzel, which was a separate Wayland client spawned per use. That
// worked, and it worked well — but it meant the shell could not draw icons
// (fuzzel's dmenu mode has none), could not show an entry's state, and had to
// write its own idea of the theme into a fuzzel.ini to be themed at all. Moving
// the picker into the shell makes those free.
//
// How a caller asks for one:
//
//   pick --title theme --on-select 'theme {}' <<< "nord\ngruvbox-dark\n..."
//
// `pick` sends the entries over IPC and exits as soon as the shell has them, so
// the caller's script is not left waiting on a menu it cannot see. The chosen
// value comes back as `{}` in `--on-select`, already shell-quoted, which is why
// a value with a space or a quote in it cannot break the command it is spliced
// into. A caller with more than one step chains them: the command for the first
// pick opens the second.
//
// The request arrives as a *path* to a file holding the JSON, not as the JSON
// itself. A single command-line argument is capped at 128KB by the kernel, and
// the emoji list is twice that: passed inline it failed with a bare "Argument
// list too long" from whichever tool happened to be moving it, which is a cliff
// to leave sitting in a picker at a size nobody can predict. `blockLoading`
// makes the read synchronous, so the shell has the request before the IPC call
// returns and the caller can delete the file immediately afterwards.
//
// There is deliberately no fallback to fuzzel. A picker that only sometimes
// exists is a picker whose keyboard layout you cannot learn; and the case that
// would need a fallback — the shell not running — is the case where a broken
// shell is what you are trying to fix, so the one thing you cannot do is pick
// something to fix it with. `pick` fails loudly instead.
QtObject {
  id: root

  // The request file, set by open() before it is read.
  //
  // Read with a process rather than a FileView. A FileView's blockLoading gives a
  // synchronous read when the path is set at construction — which is how the
  // bar's config and the theme's state file use it — but not when the path is
  // changed later: there the read is queued, so text() came back with the
  // *previous* request or with nothing at all. That showed as a picker opening
  // under the last caller's title, and then as no picker at all once the caller
  // had deleted the file on its way out.
  //
  // A process is asynchronous either way, which is why the file now outlives the
  // call and the shell removes it once it has the contents. `$1` rather than the
  // path spliced into the command, so a path with a space in it needs no quoting.
  property string requestPath: ""

  property Process requestReader: Process {
    command: [
      "sh",
      "-c",
      "cat -- \"$1\"; rm -f -- \"$1\"",
      "read-request",
      root.requestPath
    ]

    stdout: StdioCollector {
      onStreamFinished: root.applyRequest(this.text)
    }
  }

  // Shown. Gates the window's visibility and its keyboard focus: the picker only
  // takes the keyboard while it is up, or the compositor would never deliver keys
  // to the windows underneath.
  property bool shown: false

  // "list" picks from the entries. "input" is a bare text field with no list —
  // what fuzzel's --prompt-only gave, and what a reminder's message needs.
  property string mode: "list"

  // Whether Enter on an empty input field counts as an answer. Off by default,
  // because an empty answer is usually no answer. On for a prompt with a
  // sensible default — a reminder's message — where leaving it blank is a real
  // choice and refusing to accept it would be the picker overriding the caller.
  property bool allowEmpty: false

  // Draw a dimmed group line above each run of entries sharing a group. On for
  // the menu, where the group is a path prefix; off for the small pickers, whose
  // three entries do not need dividing.
  property bool grouped: false

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

  readonly property bool isInput: root.mode === "input"
  readonly property bool hasResults: root.results.length > 0
  readonly property var current:
    root.hasResults && root.selected >= 0 && root.selected < root.results.length
      ? root.results[root.selected].row
      : null

  // How many rows the list shows at once. A cap rather than a height because the
  // entries are of one kind and the picker is a panel, not a window.
  readonly property int maxVisible: 12

  // The group path the row at `index` should draw, or "" when the row above it
  // is in the same one.
  //
  // A group's path is a prefix on each of its entries, and drawn on every one of
  // them a run of twelve capture entries says "Capture" twelve times, burying
  // the labels the prefix is there to organise. Drawn on the first row of each
  // run — and wherever a filter breaks the run in two — it reads as a heading
  // without costing the line of height a heading would.
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

  // Take the request at `path` and show it. The ack is returned as soon as the
  // read is under way rather than when it finishes: `pick` exits on it, and what
  // the caller needs to know is that the shell has taken the request, not that a
  // menu has been drawn — it has already gone by then either way.
  function open(path) {
    root.requestPath = String(path !== undefined && path !== null ? path : "")

    // Restarted rather than merely started: the process has to run again for a
    // second request, and `running` stays true after the first.
    requestReader.running = false
    requestReader.running = true

    return "ok"
  }

  function applyRequest(raw) {
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

    root.present(request)
  }

  // Show a request that is already an object. `pick` arrives here by way of the
  // file above; the menu, which is built in the shell, comes straight here.
  function present(request) {
    // A request arriving while a picker is up replaces it. The alternative —
    // ignoring it — leaves the caller with a menu that never opens and no way
    // to tell that from one that was dismissed.
    root.title = String(request.title !== undefined ? request.title : "")
    root.placeholder = String(request.placeholder !== undefined ? request.placeholder : "")
    root.mode = String(request.mode !== undefined ? request.mode : "list")
    root.allowEmpty = !!request.allowEmpty
    root.grouped = !!request.grouped
    root.onSelect = String(request.onSelect !== undefined ? request.onSelect : "")
    root.onCancel = String(request.onCancel !== undefined ? request.onCancel : "")
    root.entries = request.entries !== undefined ? request.entries : []
    root.query = ""
    // Reset rather than carried over: the selection left behind by the previous
    // request can point into the middle of this one's list.
    root.selected = 0
    root.shown = true

    root.apply()
  }

  function apply() {
    if (root.isInput) {
      root.results = []
      return
    }

    root.results = Fuzzy.filter(root.entries, root.query)

    // The selection cannot point past the end of a list that just shrank under
    // it, which is what typing does to the last entry.
    if (root.selected >= root.results.length) root.selected = Math.max(0, root.results.length - 1)
  }

  function setQuery(text) {
    root.query = String(text)
    // Back to the top on every keystroke: the entry you were on is very likely
    // not the entry at index 0 of the new results, and staying put reads as the
    // list ignoring the search.
    root.selected = 0
    root.apply()
  }

  function move(delta) {
    if (root.results.length === 0) return

    let next = root.selected + delta
    if (next < 0) next = 0
    if (next > root.results.length - 1) next = root.results.length - 1
    root.selected = next
  }

  // A page is a visible screen of rows rather than a tenth of the list, so a
  // jump lands somewhere you can see.
  function page(direction) {
    root.move(direction * (root.maxVisible - 1))
  }

  function first() {
    root.selected = 0
  }

  function last() {
    root.selected = Math.max(0, root.results.length - 1)
  }

  function accept() {
    // Read before dismissing: dismiss() clears the callbacks, so asking for them
    // afterwards asks an empty string for a command that was there a moment ago.
    const select = root.onSelect

    if (root.isInput) {
      // Text mode's value is whatever was typed. An empty one is a cancellation
      // rather than a choice, unless the caller said an empty answer is one: a
      // reminder whose message defaults to "Reminder" has to be able to accept
      // a blank.
      const typed = String(root.query)
      if (typed.length === 0 && !root.allowEmpty) {
        root.dismiss()
        return
      }
      root.dismiss()
      root.runTemplate(select, typed)
      return
    }

    const entry = root.current
    if (!entry) {
      root.dismiss()
      return
    }

    const value = String(entry.value !== undefined && entry.value !== null ? entry.value : entry.label)

    // An entry's own command wins over the request's template. The menu uses
    // this: its seventy-odd entries each run something different, where every
    // other caller runs the same command with a different argument.
    const own = String(entry.run !== undefined && entry.run !== null ? entry.run : "")

    // An application from the menu carries its desktop entry, which runs without
    // a shell in between.
    const app = entry.app

    root.dismiss()
    if (app) MenuHost.launch(app)
    else if (own.length > 0) Commands.run(own)
    else root.runTemplate(select, value)
  }

  function dismiss() {
    const cancel = root.onCancel

    // The entries and the query are deliberately left as they are. The surface
    // stays on screen for the length of its fade, and emptying the list out from
    // under it would collapse the card halfway through that. The next request
    // overwrites both, and the callbacks go now, so nothing can fire twice.
    root.shown = false
    root.onSelect = ""
    root.onCancel = ""

    if (cancel.length > 0) Commands.run(cancel)
  }

  // Splice a value into a command template, quoting it here rather than leaving
  // it to the caller.
  function runTemplate(template, value) {
    const line = String(template !== undefined && template !== null ? template : "")
    if (line.length === 0) return
    Commands.run(line.split("{}").join(Util.shellQuote(value)))
  }
}