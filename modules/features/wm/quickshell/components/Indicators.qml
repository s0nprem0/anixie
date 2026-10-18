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

  // Re-read often enough that a change made elsewhere — systemd stopping the
  // idle daemon, hyprsunset switching profile on its own timetable — is picked
  // up. Those cannot be tracked from this widget's own clicks, which is why
  // they are polled. Silencing is not: the notification daemon lives in this
  // shell, so its state is read directly.
  readonly property int pollMs: 4000

  readonly property bool dnd: NotificationHost.doNotDisturb
  property bool idleStopped: false
  property int nightTemperature: 0

  // How many reminders are queued. Counted rather than listed, so the poll is a
  // number to compare rather than a table to parse.
  property int reminderCount: 0

  // hyprsunset reports its current temperature, and identity — the value the
  // daytime profile uses — leaves that reading untouched rather than clearing
  // it, so "warmer than neutral" is what tells us a tint is actually applied.
  readonly property bool nightlight: root.nightTemperature > 0 && root.nightTemperature < 6000

  readonly property var shown: {
    const list = []
    if (root.wanted("Dnd") && (root.alwaysShow || root.dnd)) list.push("Dnd")
    if (root.wanted("Idle") && (root.alwaysShow || root.idleStopped)) list.push("Idle")
    if (root.wanted("NightLight") && (root.alwaysShow || root.nightlight)) list.push("NightLight")
    if (root.wanted("Reminder") && (root.alwaysShow || root.reminderCount > 0)) list.push("Reminder")
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

        sourceComponent: modelData === "Dnd" ? dndIndicator
          : modelData === "NightLight" ? nightIndicator
          : modelData === "Reminder" ? reminderIndicator
          : idleIndicator
      }
    }
  }

  Component {
    id: dndIndicator

    WidgetButton {
      text: Util.bellSlash
      fontSize: Style.bar.iconFont
      tooltipText: root.dnd ? "Notifications silenced · click to allow" : "Notifications allowed"
      active: root.dnd
      selected: root.dnd
      dimmed: !root.dnd
      onPressed: function () { NotificationHost.toggle() }
    }
  }

  Component {
    id: idleIndicator

    WidgetButton {
      text: Util.coffee
      fontSize: Style.bar.iconFont
      tooltipText: root.idleStopped ? "Idle lock off · click to restore" : "Idle lock on"
      active: root.idleStopped
      selected: root.idleStopped
      dimmed: !root.idleStopped
      onPressed: function () { idleToggle.running = true }
    }
  }

  Component {
    id: nightIndicator

    WidgetButton {
      text: Util.moon
      fontSize: Style.bar.iconFont
      tooltipText: root.nightlight ? "Night light on · click to turn off" : "Night light off"
      active: root.nightlight
      selected: root.nightlight
      dimmed: !root.nightlight
      onPressed: function () { nightToggle.running = true }
    }
  }

  Component {
    id: reminderIndicator

    // BarIconButton rather than WidgetButton: this one shows a glyph *and* a
    // count, and a WidgetButton draws one or the other.
    BarIconButton {
      text: Util.clock
      labelText: String(root.reminderCount)
      fontSize: Style.bar.iconFont
      tooltipText: root.reminderCount === 1
        ? "1 reminder queued · click to see it"
        : root.reminderCount + " reminders queued · click to see them"
      active: true
      selected: true
      // Status rather than a switch: there is no mode to toggle, so a click
      // shows what is queued instead of changing anything.
      onPressed: function () { reminderShow.running = true }
    }
  }

  // ---- queued reminders, via the reminder command ----
  //
  // The count only. `reminder show` prints a systemd table, and parsing that on
  // every poll to find a number is work the command can do once.
  Process {
    id: reminderQuery
    command: ["sh", "-c", "reminder count 2>/dev/null || echo 0"]
    stdout: StdioCollector {
      onStreamFinished: {
        const n = parseInt(this.text.trim(), 10)
        root.reminderCount = isFinite(n) && n > 0 ? n : 0
      }
    }
  }

  // The list, as a notification: readable without leaving the desktop, and it
  // goes into the history like anything else. Read once into a variable rather
  // than piped, because notify-send takes the body as an argument.
  Process {
    id: reminderShow
    command: ["sh", "-c",
      "list=$(reminder show); notify-send -a reminders 'Queued reminders' \"$list\""]
    onExited: reminderQuery.running = true
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

  // ---- night light, via hyprsunset ----
  Process {
    id: nightQuery
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      onStreamFinished: {
        const n = parseInt(this.text.trim(), 10)
        root.nightTemperature = isFinite(n) ? n : 0
      }
    }
  }

  // 4000 is a warm tint; 6500 is the neutral it returns to. Read first so the
  // direction is chosen from the same number the indicator is showing.
  Process {
    id: nightToggle
    command: ["sh", "-c",
      "t=$(hyprctl hyprsunset temperature 2>/dev/null)"
      + " && if [ -n \"$t\" ] && [ \"$t\" -lt 6000 ]; then"
      + " hyprctl hyprsunset temperature 6500 >/dev/null;"
      + " else hyprctl hyprsunset temperature 4000 >/dev/null; fi"]
    onExited: nightQuery.running = true
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      idleQuery.running = true
      nightQuery.running = true
      reminderQuery.running = true
    }
  }
}
