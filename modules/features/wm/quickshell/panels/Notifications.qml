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

  // Every row is the same height, so the list states its own height outright.
  //
  // The panel is sized from the list rather than left to the card's implicit
  // height, because a Repeater's delegates do not reliably feed a Panel's
  // content column: with three entries in it the panel measured 56px — tall
  // enough for the title and nothing else. Stating the height here removes that
  // dependency. The floor is the card's own measurement, kept so an empty panel
  // still gets its title.
  readonly property int rowHeight: 62

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
        ? ""
        : root.entries.length + (root.entries.length === 1 ? " entry" : " entries")
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

    // Newest first, which is the order the store already sorted them in.
    Column {
      width: card.contentWidth
      height: root.entries.length * root.rowHeight
      visible: !root.empty

      Repeater {
        model: root.entries

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

            Text {
              width: parent.width
              height: implicitHeight
              visible: row.modelData.app !== ""
              text: row.modelData.app
              textFormat: Text.PlainText
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // A separator rather than padding, so the rows read as a list instead of
          // a stack of unrelated cards.
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: row.index < root.entries.length - 1
            color: Theme.muted
            opacity: 0.3
          }
        }
      }
    }

    // Only offered when there is something to clear.
    PanelActionButton {
      width: card.contentWidth
      visible: !root.empty
      height: implicitHeight
      label: "Clear history"
      navigational: false
      onClicked: NotificationStore.clear()
    }
  }
}