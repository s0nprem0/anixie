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

  // PanelRow's height grows with the text-size setting, so the list's explicit
  // height has to grow with it. A fixed 20 works only at the default size.
  readonly property int rowHeight: Math.max(20, Style.font.body + 8)

  Panel {
    id: card
    anchors.fill: parent
    clip: true

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
      label: "Now"
      value: ScreentimeStore.idleNow
        ? "Idle"
        : (ScreentimeStore.currentApp === "" ? "—" : ScreentimeStore.appLabel(ScreentimeStore.currentApp))
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
    Column {
      width: card.contentWidth
      height: root.leaders.length * root.rowHeight

      Repeater {
        model: root.leaders

        delegate: PanelRow {
          required property var modelData
          width: parent.width
          height: root.rowHeight
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
      onClicked: confirmReset.open()
    }
  }

  ConfirmDialog {
    id: confirmReset
    anchors.fill: parent
    text: "Reset screen time?"
    detail: "Today's totals and per-app breakdown will be cleared. Focus mode is not affected."
    confirmText: "Reset"
    danger: true
    onConfirmed: ScreentimeStore.reset()
  }
}
