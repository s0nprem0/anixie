pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "Jsonc.js" as Jsonc

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
    if (!root.tree) root.tree = root.parseTree()
    return root.apps.length
  }

  // A `list` source's children, as { label, icon, app }.
  function listOf(source) {
    switch (source) {
    case "apps":
      return root.apps.map(function (entry) {
        return { label: entry.name, icon: entry.icon, app: entry }
      })
    case "themes":
      return Theme.names().map(function (name) {
        return { label: name, icon: "", app: null }
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
    }
    console.warn("menu: no state called \"" + source + "\"")
    return ""
  }

  // Whether a `when` source holds. A row that only makes sense some of the time
  // — "Stop screen recording" — is left out the rest of it.
  function holds(source) {
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
              state: "",
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
          add({ label: node.label, group: group, icon: entry.icon, state: "", app: entry, run: "" })
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
    const entries = root.shown(group)
    if (entries.length === 0) {
      console.warn("menu: nothing to show" + (group ? " under \"" + group + "\"" : ""))
      return
    }

    PickHost.present({
      title: group !== "" ? group : "menu",
      grouped: true,
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

  // Run a desktop entry. Detached, so an application outlives a shell restart
  // rather than being taken down with it, and from the entry's own working
  // directory, which `command` alone does not carry.
  function launch(entry) {
    if (!entry) return
    const command = entry.runInTerminal
      ? [root.terminal, "-e"].concat(entry.command)
      : entry.command
    Quickshell.execDetached({ command: command, workingDirectory: entry.workingDirectory })
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
