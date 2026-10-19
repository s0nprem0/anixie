import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// Indicators for state that is otherwise invisible from the bar: notifications
// silenced, the idle lock off, the night light on, and reminders queued.
//
// Each shows only while its state is live, unless `alwaysShow` keeps it in place
// dimmed — otherwise a bar whose layout is hand-written would reshuffle every
// time one came or went.
//
// The model holds only the indicators currently shown rather than every
// indicator with the rest hidden, so there are no hidden children to lay out.
//
// Nothing here polls. The values come from IndicatorHost, which `toggle` and
// `reminder` update when they change something. A click runs the same `toggle`
// command the keys run, so the click and the key cannot disagree.
BarWidget {
  id: root

  // Which indicators to show, by name and in the order listed. Empty means all.
  readonly property var items: root.setting("items", [])
  readonly property bool alwaysShow: root.setting("alwaysShow", false)

  function wanted(id) {
    const list = root.items
    return list.length === 0 || list.indexOf(id) !== -1
  }

  readonly property bool dnd: NotificationHost.doNotDisturb
  readonly property bool idleStopped: IndicatorHost.idleStopped
  readonly property bool stayAwake: IndicatorHost.stayAwake
  readonly property bool nightlight: IndicatorHost.nightlight
  readonly property int reminderCount: IndicatorHost.reminderCount

  readonly property var shown: {
    const list = []
    if (root.wanted("Dnd") && (root.alwaysShow || root.dnd)) list.push("Dnd")
    if (root.wanted("Idle") && (root.alwaysShow || root.idleStopped)) list.push("Idle")
    if (root.wanted("StayAwake") && (root.alwaysShow || root.stayAwake)) list.push("StayAwake")
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
          : modelData === "StayAwake" ? stayAwakeIndicator
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
      onPressed: function () { Commands.run("toggle idle") }
    }
  }

  Component {
    id: stayAwakeIndicator

    WidgetButton {
      text: Util.bolt
      fontSize: Style.bar.iconFont
      tooltipText: root.stayAwake ? "Holding off sleep · click to release" : "Sleep is not held"
      active: root.stayAwake
      selected: root.stayAwake
      dimmed: !root.stayAwake
      onPressed: function () { Commands.run("toggle stayawake") }
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
      onPressed: function () { Commands.run("toggle nightlight") }
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
      onPressed: function () {
        Commands.run("list=$(reminder show); notify-send -a reminders 'Queued reminders' \"$list\"")
      }
    }
  }
}
