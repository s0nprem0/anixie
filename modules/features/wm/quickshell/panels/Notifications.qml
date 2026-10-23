import QtQuick
import ".."
import "../Ui"

// Notification history: everything the daemon has seen since the last time it
// was cleared, newest first.
//
// The rows are the entries NotificationStore parsed off disk, not live
// notifications, so this is readable after the fact — which is the point of it.
// A live notification is still on screen and its actions still work; a history
// row is a record, and the client's actions died with it.
Item {
  id: root

  // Read on open rather than kept up to date, so the panel costs nothing while
  // it is closed and cannot show a stale list the moment it appears.
  Component.onCompleted: NotificationStore.refresh()

  readonly property var entries: NotificationStore.entries
  readonly property bool empty: root.entries.length === 0

  // History grouped by sender, groups ordered by their newest entry. A run of
  // fifty chat messages used to bury every other source in one flat list; the
  // source header is what makes the list scannable again.
  readonly property var entryGroups: {
    const byApp = ({})
    const order = []
    for (const entry of root.entries) {
      const app = String(entry.app || "Unknown")
      if (!byApp[app]) {
        byApp[app] = { app: app, entries: [] }
        order.push(app)
      }
      byApp[app].entries.push(entry)
    }
    return order.map(function (app) { return byApp[app] })
  }

  readonly property var quietSources: {
    NotificationHost.snoozes
    NotificationHost.globalSnoozeUntil
    return NotificationHost.quietSources()
  }

  function quietUntil(stamp) {
    const date = new Date(Number(stamp || 0) * 1000)
    return "until " + date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }

  function sourceLabel(value) {
    const name = String(value || "")
    if (name === "*") return "Everything"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  // Every row is the same height, so the list states its own height outright.
  //
  // The panel is sized from the list rather than left to the card's implicit
  // height, because a Repeater's delegates do not reliably feed a Panel's
  // content column: with three entries in it the panel measured 56px — tall
  // enough for the title and nothing else. Stating the height here removes that
  // dependency. The floor is the card's own measurement, kept so an empty panel
  // still gets its title.
  readonly property int rowHeight: 62
  readonly property int groupHeaderHeight: Style.space(24)

  implicitWidth: Style.space(340)
  // The card sizes itself, and caps what it will show: a week of notifications
  // is longer than a screen, and what will not fit scrolls rather than running
  // off the bottom of the display.
  implicitHeight: card.implicitHeight

  // Reload when the panel is reopened on the same instance, which happens
  // whenever another module's panel is closed and this one is opened again from
  // a freshly built component.
  onVisibleChanged: if (root.visible) NotificationStore.refresh()

  function ago(stamp) {
    const seconds = Math.max(0, Math.floor((Date.now() - stamp) / 1000))
    if (seconds < 60) return "just now"

    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"

    const hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"

    const days = Math.floor(hours / 24)
    if (days < 7) return days + "d ago"

    const date = new Date(stamp)
    return date.toLocaleDateString()
  }

  Panel {
    id: card
    anchors.fill: parent

    PanelHero {
      width: card.contentWidth
      glyph: Util.bell
      title: "Notifications"
      subtitle: root.empty
        ? (root.quietSources.length > 0 ? "quiet" : "")
        : root.entries.length + (root.entries.length === 1 ? " entry" : " entries")
          + (root.quietSources.length > 0 ? "  ·  " + root.quietSources.length + " quiet" : "")
    }

    // The sources currently held back, with the time they come back. A snooze is
    // not DND: it has an end, and the panel is where that end is visible.
    Column {
      width: card.contentWidth
      visible: root.quietSources.length > 0
      spacing: Style.space(2)

      Text {
        width: parent.width
        height: implicitHeight
        text: "Quiet"
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.quietSources

        delegate: PanelActionButton {
          required property var modelData

          width: card.contentWidth
          height: implicitHeight
          label: "Resume " + root.sourceLabel(modelData.label)
          value: root.quietUntil(modelData.until)
          navigational: false
          onClicked: NotificationHost.unsnooze(modelData.key)
        }
      }
    }

    Text {
      width: card.contentWidth
      visible: root.empty
      height: implicitHeight
      text: "Nothing yet. Notifications show up here once they have been dismissed."
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      renderType: Text.NativeRendering
    }

    // Newest first, grouped by sender. The row heights are stated explicitly for
    // the same reason as before: a Repeater does not feed a Panel's content
    // column reliably, so the list owns its height.
    Column {
      width: card.contentWidth
      height: root.entryGroups.length * root.groupHeaderHeight + root.entries.length * root.rowHeight
      visible: !root.empty
      spacing: 0

      Repeater {
        model: root.entryGroups

        delegate: Column {
          id: groupDelegate
          required property var modelData

          width: parent.width
          spacing: 0

          Text {
            width: parent.width
            height: root.groupHeaderHeight
            text: modelData.app + "  ·  " + modelData.entries.length
            textFormat: Text.PlainText
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Repeater {
            model: modelData.entries

            delegate: Item {
              id: row

              required property var modelData

              width: parent.width
              height: root.rowHeight

              Column {
                id: rowBody

                width: parent.width
                height: root.rowHeight - Style.space(12)
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  height: implicitHeight
                  spacing: Style.space(6)

                  Text {
                    width: Math.max(0, parent.width - timeText.implicitWidth - Style.space(6))
                    // Explicit, like every other row in this repo: a Column positions
                    // its children by their height rather than their implicit height,
                    // and Text leaves `height` at 0 unless it is stated.
                    height: implicitHeight
                    text: row.modelData.summary !== "" ? row.modelData.summary : "(no summary)"
                    textFormat: Text.PlainText
                    color: Theme.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                  }

                  Text {
                    id: timeText

                    height: implicitHeight
                    text: root.ago(row.modelData.timestamp)
                    color: Theme.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  height: implicitHeight
                  visible: row.modelData.body !== ""
                  text: row.modelData.body
                  textFormat: Text.PlainText
                  color: Theme.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }

              // A separator rather than padding, so the rows read as a list instead of
              // a stack of unrelated cards.
              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                visible: row.index < groupDelegate.modelData.entries.length - 1
                color: Theme.muted
                opacity: 0.3
              }
            }
          }
        }
      }
    }

    // Replay the newest entries in the same cards used for live notifications.
    // The popup is a separate window, so close the panel first rather than
    // leaving it covering the desktop underneath the replay.
    PanelActionButton {
      width: card.contentWidth
      visible: !root.empty
      height: implicitHeight
      label: "Replay last 10"
      navigational: false
      onClicked: {
        NotificationHost.replay()
        PanelHost.closeFocused()
      }
    }

    // Only offered when there is something to clear.
    PanelActionButton {
      width: card.contentWidth
      visible: !root.empty
      height: implicitHeight
      label: "Clear history"
      navigational: false
      onClicked: confirmClear.open()
    }
  }

  ConfirmDialog {
    id: confirmClear
    anchors.fill: parent
    text: "Clear notification history?"
    detail: "This removes every archived notification. The live popups are not affected."
    confirmText: "Clear"
    cancelText: "Keep"
    danger: true
    onConfirmed: NotificationStore.clear()
  }
}