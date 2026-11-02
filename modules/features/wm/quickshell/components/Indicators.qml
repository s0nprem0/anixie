import QtQuick
import ".."
import "../Ui"
import Quickshell.Io

// Indicators for state that is otherwise invisible from the bar.
BarWidget {
  id: root

  readonly property var configuredItems: {
    const raw = root.setting ? root.setting("items", []) : []
    if (!Array.isArray(raw)) return []
    const out = []
    for (let i = 0; i < raw.length; i++) {
      if (raw[i] !== undefined && raw[i] !== null) out.push(String(raw[i]))
    }
    return out
  }
  readonly property var items: root.configuredItems
  readonly property bool alwaysShow: root.setting ? !!root.setting("alwaysShow", false) : false

  function wanted(id) {
    const list = root.items
    const allowed = ["Dnd", "Idle", "StayAwake", "NightLight", "Reminder", "Focus"]
    if (allowed.indexOf(String(id)) === -1) return false
    if (!Array.isArray(list) || list.length === 0) return true
    return list.indexOf(String(id)) !== -1
  }

  readonly property bool dndGlobal: NotificationHost ? !!NotificationHost.doNotDisturb : false
  readonly property bool hasSnoozes: NotificationHost ? !!NotificationHost.hasSnoozes : false
  readonly property bool silenced: root.dndGlobal || root.hasSnoozes
  readonly property bool dnd: root.dndGlobal
  readonly property bool idleStopped: IndicatorHost ? !!IndicatorHost.idleStopped : false
  readonly property bool stayAwake: IndicatorHost ? !!IndicatorHost.stayAwake : false
  readonly property bool nightlight: IndicatorHost ? !!IndicatorHost.nightlight : false
  readonly property int reminderCount: {
    const n = IndicatorHost ? Number(IndicatorHost.reminderCount) : 0
    if (!isFinite(n) || n <= 0) return 0
    return Math.floor(n)
  }
  readonly property bool focusMode: IndicatorHost ? !!IndicatorHost.focusActive : false
  readonly property string focusLabel: FocusHost && FocusHost.remainingLabel ? String(FocusHost.remainingLabel) : ""

  readonly property var shown: {
    const list = []
    if (root.wanted("Dnd") && (root.alwaysShow || root.silenced)) list.push("Dnd")
    if (root.wanted("Idle") && (root.alwaysShow || root.idleStopped)) list.push("Idle")
    if (root.wanted("StayAwake") && (root.alwaysShow || root.stayAwake)) list.push("StayAwake")
    if (root.wanted("NightLight") && (root.alwaysShow || root.nightlight)) list.push("NightLight")
    if (root.wanted("Reminder") && (root.alwaysShow || root.reminderCount > 0)) list.push("Reminder")
    if (root.wanted("Focus") && (root.alwaysShow || root.focusMode)) list.push("Focus")
    return list
  }

  readonly property bool anyShown: root.shown.length > 0

  wantsSlot: root.anyShown
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
          : modelData === "Focus" ? focusIndicator
          : idleIndicator
      }
    }
  }

  Component {
    id: dndIndicator

    WidgetButton {
      text: Util.bellSlash
      fontSize: Style.bar.iconFont
      tooltipText: root.dndGlobal
        ? "Do Not Disturb on · click to turn off"
        : (root.hasSnoozes ? "Notifications snoozed · click to clear snoozes" : "Notifications allowed")
      active: root.dndGlobal
      selected: root.silenced
      dimmed: !root.silenced
      onPressed: function () {
        if (root.dndGlobal) {
          if (NotificationHost && NotificationHost.setDnd) NotificationHost.setDnd(false)
          return
        }
        if (root.hasSnoozes && NotificationHost && NotificationHost.quietSources) {
          const sources = NotificationHost.quietSources()
          if (Array.isArray(sources)) {
            for (let i = 0; i < sources.length; i++) {
              const s = sources[i]
              if (s && s.key !== undefined) {
                try { NotificationHost.unsnooze(s.key) } catch (e) {}
              }
            }
          }
          return
        }
        if (NotificationHost && NotificationHost.setDnd) NotificationHost.setDnd(true)
      }
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

    BarIconButton {
      text: Util.clock
      labelText: String(root.reminderCount)
      fontSize: Style.bar.iconFont
      tooltipText: root.reminderCount === 1
        ? "1 reminder queued · click to see"
        : root.reminderCount + " reminders queued · click to see"
      active: true
      selected: true
      onPressed: function () {
        Commands.run("reminder show 2>/dev/null | { IFS= read -r first || exit 0; if [ -n \"$first\" ]; then notify-send -a reminders 'Queued reminders' \"$(reminder show 2>/dev/null)\"; fi; }")
      }
    }
  }

  Component {
    id: focusIndicator

    WidgetButton {
      text: Util.clock
      fontSize: Style.bar.iconFont
      tooltipText: root.focusLabel !== ""
        ? "Focus · " + root.focusLabel + " left · click for screen time"
        : "Focus mode · click for screen time"
      active: true
      selected: true
      onPressed: function () { Commands.run("screentime panel") }
    }
  }

}
