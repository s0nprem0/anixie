import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// Indicators for state that is otherwise invisible from the bar: notifications
// silenced, and the idle daemon stopped so the screen will not lock.
//
// Each shows only while its state is live, unless `alwaysShow` keeps it in place
// dimmed — otherwise a bar whose layout is hand-written would reshuffle every
// time one came or went.
//
// The model holds only the indicators currently shown rather than every
// indicator with the rest hidden, so there are no hidden children to lay out.
BarWidget {
  id: root

  // Which indicators to show, by name and in the order listed. Empty means all.
  readonly property var items: root.setting("items", [])
  readonly property bool alwaysShow: root.setting("alwaysShow", false)

  function wanted(id) {
    const list = root.items
    return list.length === 0 || list.indexOf(id) !== -1
  }

  // Re-read often enough that a change made elsewhere — a keybind silencing
  // notifications, systemd stopping the daemon — is picked up. These cannot be
  // tracked from this widget's own clicks, which is the whole reason they are
  // polled rather than toggled locally.
  readonly property int pollMs: 4000

  property bool dnd: false
  property bool idleStopped: false

  readonly property var shown: {
    const list = []
    if (root.wanted("Dnd") && (root.alwaysShow || root.dnd)) list.push("Dnd")
    if (root.wanted("Idle") && (root.alwaysShow || root.idleStopped)) list.push("Idle")
    return list
  }

  readonly property bool anyShown: root.shown.length > 0

  visible: root.anyShown
  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      model: root.shown

      delegate: Loader {
        required property string modelData

        sourceComponent: modelData === "Dnd" ? dndIndicator : idleIndicator
      }
    }
  }

  Component {
    id: dndIndicator

    WidgetButton {
      text: Util.bellSlash
      fontSize: Style.bar.iconFont
      tooltipText: root.dnd ? "Notifications silenced" : "Notifications allowed"
      active: root.dnd
      dimmed: !root.dnd
      onPressed: function () { dndToggle.running = true }
    }
  }

  Component {
    id: idleIndicator

    WidgetButton {
      text: Util.coffee
      fontSize: Style.bar.iconFont
      tooltipText: root.idleStopped ? "Idle lock off · click to restore" : "Idle lock on"
      active: root.idleStopped
      dimmed: !root.idleStopped
      onPressed: function () { idleToggle.running = true }
    }
  }

  // ---- notifications silenced, via mako ----
  Process {
    id: dndQuery
    command: ["makoctl", "mode"]
    stdout: StdioCollector {
      // mako lists the active modes one per line; do-not-disturb is one of them.
      onStreamFinished: root.dnd = this.text.indexOf("do-not-disturb") !== -1
    }
  }

  Process {
    id: dndToggle
    command: ["makoctl", "mode", "-t", "do-not-disturb"]
    onExited: dndQuery.running = true
  }

  // ---- idle daemon stopped, via systemd ----
  Process {
    id: idleQuery
    command: ["systemctl", "--user", "is-active", "hypridle"]
    stdout: StdioCollector {
      onStreamFinished: root.idleStopped = this.text.trim() !== "active"
    }
  }

  // Toggled in one shell line so there is a single process to wait on; is-active
  // exits non-zero when the unit is not running, which is what selects the arm.
  Process {
    id: idleToggle
    command: ["sh", "-c",
      "systemctl --user is-active --quiet hypridle"
      + " && systemctl --user stop hypridle"
      + " || systemctl --user start hypridle"]
    onExited: idleQuery.running = true
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      dndQuery.running = true
      idleQuery.running = true
    }
  }
}
