import QtQuick
import ".."
import "../Ui"

// Today's screen time and the focus controls.
//
// The two belong together: what you spent the day doing is the reason to start a
// focus block, and the remaining time is the reason to stop one. One panel means
// one place to look rather than a timer hidden in a menu.
Item {
  id: root

  implicitWidth: Style.space(330)
  implicitHeight: card.implicitHeight

  readonly property var leaders: ScreentimeStore.topApps(5)

  Panel {
    id: card
    anchors.fill: parent

    PanelHero {
      width: card.contentWidth
      glyph: Util.clock
      title: "Screen time"
      subtitle: ScreentimeStore.todayLabel
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "TODAY"
    }

    PanelRow {
      width: card.contentWidth
      label: "Active"
      value: ScreentimeStore.formatDuration(ScreentimeStore.activeSeconds)
    }

    PanelRow {
      width: card.contentWidth
      label: "Idle"
      value: ScreentimeStore.formatDuration(ScreentimeStore.idleSeconds)
    }

    PanelRow {
      width: card.contentWidth
      label: "Total"
      value: ScreentimeStore.formatDuration(ScreentimeStore.totalSeconds)
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "TOP APPS"
    }

    // The Repeater needs an explicit height: its delegates do not reliably feed
    // a Panel's content column (the notifications panel learned the same
    // lesson), and an unmeasured list makes the card short enough to hide it.
    Item {
      width: card.contentWidth
      height: root.leaders.length * 20

      Repeater {
        model: root.leaders

        delegate: PanelRow {
          required property var modelData
          width: parent.width
          label: ScreentimeStore.appLabel(modelData.app)
          value: ScreentimeStore.formatDuration(modelData.seconds)
        }
      }
    }

    PanelRow {
      width: card.contentWidth
      label: "No activity recorded yet"
      visible: root.leaders.length === 0
      height: visible ? implicitHeight : 0
    }

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "FOCUS"
    }

    PanelRow {
      width: card.contentWidth
      label: "Remaining"
      value: FocusHost.remainingLabel
      visible: FocusHost.active
      height: visible ? implicitHeight : 0
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Focus for 25 minutes"
      value: FocusHost.active ? "" : "Super+Ctrl+F"
      navigational: false
      onClicked: FocusHost.start("25")
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Focus for 50 minutes"
      navigational: false
      onClicked: FocusHost.start("50")
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Extend by 15 minutes"
      navigational: false
      available: FocusHost.active
      onClicked: FocusHost.extend("15")
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Stop focus"
      danger: true
      navigational: false
      available: FocusHost.active
      onClicked: FocusHost.stop()
    }

    PanelSeparator {}

    PanelActionButton {
      width: card.contentWidth
      label: "Reset today"
      danger: true
      navigational: false
      onClicked: ScreentimeStore.reset()
    }
  }
}
