import QtQuick
import ".."
import "../Ui"
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The keyboard layout, while there is more than one to be on.
//
// One layout is not a choice and does not need a glyph on the bar; two are, and
// the thing you want to know before typing is which one is live. Clicking
// switches, which is quicker than remembering the Hyprland bind.
//
// `hyprctl devices` is where the answer is: the `layout` field is the configured
// list and `active_layout_index` says which of it is in use. It is asked for at
// startup and whenever Hyprland says the layout changed — the module already
// has the event socket open, so the 15-second poll this used to run was asking
// the same question over and over. `configreloaded` is the other moment the
// answer can change, since it can replace the keyboard's layout list.
BarWidget {
  id: root

  property string name: ""
  property var layouts: []
  property int active: 0

  readonly property string code: root.layouts.length > root.active
    ? String(root.layouts[root.active] || "").toUpperCase()
    : ""

  readonly property bool multiple: root.layouts.length > 1

  function refresh() {
    // A reload emits one event per keyboard; the probe reads all of them.
    if (probe.running) return
    probe.running = true
  }

  function next() {
    if (root.name === "") return
    Commands.runQuoted("hyprctl", ["switchxkblayout", root.name, "next"])
    after.restart()
  }

  Process {
    id: probe
    command: ["hyprctl", "-j", "devices"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const keyboards = JSON.parse(String(this.text)).keyboards || []
          let chosen = null
          for (let i = 0; i < keyboards.length; i++) {
            const keyboard = keyboards[i]
            if (!chosen || keyboard.main === true) chosen = keyboard
          }
          if (!chosen) return

          root.name = String(chosen.name || "")
          root.layouts = String(chosen.layout || "").split(",").filter(function (item) {
            return item !== ""
          })
          root.active = Number(chosen.active_layout_index) || 0
        } catch (e) {
          root.layouts = []
        }
      }
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name === "activelayout" || event.name === "configreloaded") root.refresh()
    }
  }

  // Hyprland applies the switch, then announces it; this is only for the click
  // that asked, so the label catches up even if the announcement is missed.
  Timer {
    id: after
    interval: 350
    onTriggered: root.refresh()
  }

  wantsSlot: root.multiple
  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.keyboard
    labelText: root.vertical ? "" : root.code
    tooltipText: "Layout " + root.code + " · click for the next one"
    onPressed: function () { root.next() }
  }
}