import QtQuick
import ".."
import "../Ui"
import "../Ui/NotificationText.js" as NotificationText

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
  // Quiet notifications are written straight to history. The panel lists those
  // under their source instead of mixing them into the closed list.
  readonly property var heldEntries: root.entries.filter(function (entry) { return entry.quiet === true })
  readonly property var activeEntries: root.entries.filter(function (entry) { return entry.quiet !== true })
  readonly property bool empty: root.activeEntries.length === 0 && root.heldEntries.length === 0

  function groupBySource(list) {
    const byApp = ({})
    const order = []
    for (const entry of list) {
      const key = String(entry.sourceKey || entry.app || "unknown").toLowerCase()
      const label = String(entry.source || entry.app || "Unknown")
      if (!byApp[key]) {
        byApp[key] = { key: key, app: label, entries: [] }
        order.push(key)
      }
      byApp[key].entries.push(entry)
    }
    return order.map(function (app) { return byApp[app] })
  }

  // History grouped by sender, groups ordered by their newest entry. A run of
  // fifty chat messages used to bury every other source in one flat list; the
  // source header is what makes the list scannable again.
  readonly property var entryGroups: root.groupBySource(root.activeEntries)
  readonly property var heldGroups: root.groupBySource(root.heldEntries)

  function openSnoozeMenu(group, anchor) {
    const entries = []
    const options = NotificationHost.snoozeOptions()
    for (let i = 0; i < options.length; i++) {
      const option = options[i]
      entries.push({
        label: option.label,
        glyph: Util.clock,
        action: function () { NotificationHost.snooze(group.key, option.seconds) }
      })
    }
    entries.push({ separator: true })
    entries.push({
      label: "Snooze everything",
      glyph: Util.clock,
      action: function () { NotificationHost.snooze("*", NotificationHost.untilTomorrow()) }
    })
    ContextMenuHost.openAt(entries, anchor, 0, anchor.height)
  }

  readonly property var quietSources: {
    NotificationHost.snoozes
    NotificationHost.globalSnoozeUntil
    return NotificationHost.quietSources()
  }

  readonly property var displayOptions: [
    { label: "Focused monitor", value: "focused" },
    { label: "All monitors", value: "all" },
    { label: "Specific output", value: "specific" }
  ]

  readonly property int displayIndex: {
    for (let i = 0; i < root.displayOptions.length; i++) {
      if (root.displayOptions[i].value === NotificationHost.displayMode) return i
    }
    return 0
  }

  readonly property var screenOptions: {
    const out = []
    for (let i = 0; i < Screens.all.length; i++) {
      const name = String(Screens.all[i].name || "")
      if (name !== "") out.push({ label: name, value: name })
    }
    if (NotificationHost.displayName !== ""
        && !out.some(function (entry) { return entry.value === NotificationHost.displayName })) {
      out.push({ label: NotificationHost.displayName + " (disconnected)", value: NotificationHost.displayName })
    }
    return out
  }

  readonly property int screenIndex: {
    for (let i = 0; i < root.screenOptions.length; i++) {
      if (root.screenOptions[i].value === NotificationHost.displayName) return i
    }
    return -1
  }

  readonly property var retentionOptions: [
    { label: "24 hours", value: 24 },
    { label: "3 days", value: 72 },
    { label: "7 days", value: 168 }
  ]

  readonly property int retentionIndex: {
    for (let i = 0; i < root.retentionOptions.length; i++) {
      if (root.retentionOptions[i].value === NotificationHost.historyHours) return i
    }
    return 0
  }

  function chooseDisplay(index) {
    if (index < 0 || index >= root.displayOptions.length) return
    const value = root.displayOptions[index].value
    NotificationHost.setDisplayMode(value)
    if (value === "specific" && NotificationHost.displayName === "" && Screens.all.length > 0) {
      NotificationHost.setDisplayName(String(Screens.all[0].name || ""))
    }
  }

  function chooseScreen(index) {
    if (index < 0 || index >= root.screenOptions.length) return
    NotificationHost.setDisplayName(root.screenOptions[index].value)
  }

  function chooseRetention(index) {
    if (index < 0 || index >= root.retentionOptions.length) return
    NotificationHost.setHistoryHours(root.retentionOptions[index].value)
  }

  function quietUntil(stamp) {
    const date = new Date(Number(stamp || 0) * 1000)
    return "until " + date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }

  function sourceLabel(value) {
    const name = String(value || "")
    if (name === "*") return "Everything"
    if (name.indexOf(".") !== -1) return name
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
      subtitle: {
        const parts = []
        if (root.activeEntries.length > 0) parts.push(root.activeEntries.length + (root.activeEntries.length === 1 ? " entry" : " entries"))
        if (root.heldEntries.length > 0) parts.push(root.heldEntries.length + " held")
        if (root.quietSources.length > 0) parts.push(root.quietSources.length + " quiet")
        return parts.join("  ·  ")
      }
    }

    PanelSeparator {
      visible: root.empty
    }

    Column {
      width: card.contentWidth
      visible: root.empty
      spacing: Style.space(4)
      topPadding: Style.space(10)
      bottomPadding: Style.space(10)

      Text {
        width: parent.width
        text: "No notifications yet"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        text: "Dismissed notifications will appear here."
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }
    }

    PanelSeparator {
      visible: root.activeEntries.length > 0
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.activeEntries.length > 0
      label: "Recent"
    }

    // Newest first, grouped by sender. The row heights are stated explicitly for
    // the same reason as before: a Repeater does not feed a Panel's content
    // column reliably, so the list owns its height.
    Column {
      width: card.contentWidth
      height: root.entryGroups.length * root.groupHeaderHeight + root.activeEntries.length * root.rowHeight
      visible: root.activeEntries.length > 0
      spacing: 0

      Repeater {
        model: root.entryGroups

        delegate: Column {
          id: groupDelegate
          required property var modelData
          required property int index

          width: parent.width
          spacing: 0

          Item {
            width: parent.width
            height: root.groupHeaderHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              visible: groupDelegate.index > 0
              color: Theme.muted
              opacity: 0.3
            }

            Text {
              anchors.left: parent.left
              anchors.right: groupSnooze.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sourceLabel(modelData.app) + "  ·  " + modelData.entries.length
              textFormat: Text.PlainText
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              id: groupSnooze
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: Style.space(20)
              text: Util.clock
              color: groupSnoozeArea.containsMouse ? Theme.fg : Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              renderType: Text.NativeRendering

              MouseArea {
                id: groupSnoozeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openSnoozeMenu(groupDelegate.modelData, groupSnooze)
              }
            }
          }

          Repeater {
            model: modelData.entries

            delegate: Item {
              id: row

              required property var modelData

              width: parent.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                visible: rowMouse.containsMouse
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha)
              }

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
                    text: row.modelData.summary !== "" ? NotificationText.preview(row.modelData.summary) : "(no summary)"
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
                      + (row.modelData.closedReason ? " · " + row.modelData.closedReason : "")
                    color: Theme.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  height: implicitHeight
                  visible: row.modelData.body !== ""
                  text: NotificationText.preview(row.modelData.body)
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

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  NotificationHost.replayEntry(row.modelData)
                  PanelHost.closeFocused()
                }
              }
            }
          }
        }
      }
    }

    PanelSeparator {
      visible: root.heldEntries.length > 0
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.heldEntries.length > 0
      label: "Held"
    }

    // Held notifications are ones quiet kept off the screen. They are still
    // grouped by source, so the panel says what was missed and who it was from.
    Column {
      width: card.contentWidth
      visible: root.heldEntries.length > 0
      spacing: 0

      Repeater {
        model: root.heldGroups

        delegate: Column {
          id: heldDelegate
          required property var modelData
          required property int index

          width: parent.width
          spacing: 0

          Item {
            width: parent.width
            height: root.groupHeaderHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              visible: heldDelegate.index > 0
              color: Theme.muted
              opacity: 0.3
            }

            Text {
              anchors.left: parent.left
              anchors.right: heldSnooze.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sourceLabel(modelData.app) + "  ·  " + modelData.entries.length
              color: Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              id: heldSnooze
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: Style.space(20)
              text: Util.clock
              color: heldSnoozeArea.containsMouse ? Theme.fg : Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              renderType: Text.NativeRendering

              MouseArea {
                id: heldSnoozeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.openSnoozeMenu(heldDelegate.modelData, heldSnooze)
              }
            }
          }

          Repeater {
            model: modelData.entries

            delegate: PanelActionButton {
              required property var modelData

              width: parent.width
              height: implicitHeight
              label: NotificationText.preview(modelData.summary)
              value: (modelData.closedReason ? root.sourceLabel(modelData.closedReason) : "held")
                + "  ·  " + root.ago(modelData.timestamp)
              navigational: false
              onClicked: {
                NotificationHost.replayEntry(modelData)
                PanelHost.closeFocused()
              }
            }
          }
        }
      }
    }

    PanelActionButton {
      width: card.contentWidth
      visible: root.heldEntries.length > 0
      height: implicitHeight
      label: "Clear held"
      navigational: false
      onClicked: NotificationStore.clearHeld()
    }

    PanelSeparator {
      visible: root.quietSources.length > 0
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: root.quietSources.length > 0
      label: "Quiet"
    }

    // The sources currently held back, with the time they come back. A snooze is
    // not DND: it has an end, and the panel is where that end is visible.
    Column {
      width: card.contentWidth
      visible: root.quietSources.length > 0
      spacing: Style.space(2)

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

    PanelSeparator {
      visible: NotificationHost.sharingOfferPending
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: NotificationHost.sharingOfferPending
      label: "Screen sharing"
    }

    // The offer appears only while a portal video stream is live and nothing is
    // already quiet. It is a suggestion, not an automatic mute.
    Column {
      width: card.contentWidth
      visible: NotificationHost.sharingOfferPending
      spacing: Style.space(2)

      Text {
        width: parent.width
        height: implicitHeight
        text: "Snooze notifications while you share?"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      PanelActionButton {
        width: card.contentWidth
        height: implicitHeight
        label: "For 30 minutes"
        navigational: false
        onClicked: NotificationHost.snoozeSharingOffer(1800)
      }

      PanelActionButton {
        width: card.contentWidth
        height: implicitHeight
        label: "For 1 hour"
        navigational: false
        onClicked: NotificationHost.snoozeSharingOffer(3600)
      }

      PanelActionButton {
        width: card.contentWidth
        height: implicitHeight
        label: "For 4 hours"
        navigational: false
        onClicked: NotificationHost.snoozeSharingOffer(14400)
      }

      PanelActionButton {
        width: card.contentWidth
        height: implicitHeight
        label: "Not now"
        navigational: false
        onClicked: NotificationHost.dismissSharingOffer()
      }
    }

    PanelSeparator {
      visible: !root.empty
    }

    PanelSectionHeader {
      width: card.contentWidth
      visible: !root.empty
      label: "Actions"
    }

    // A source can be snoozed from its group header below, but this is the
    // one-row way to quiet everything without waiting for a card.
    PanelActionButton {
      id: snoozeAll
      width: card.contentWidth
      visible: !root.empty
      height: implicitHeight
      label: "Snooze everything"
      navigational: false
      onClicked: root.openSnoozeMenu({ key: "*" }, snoozeAll)
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

    PanelSeparator {}

    PanelSectionHeader {
      width: card.contentWidth
      label: "Preferences"
    }

    Column {
      width: card.contentWidth
      spacing: Style.space(4)

      Text {
        width: parent.width
        height: implicitHeight
        text: "Show notifications on"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Dropdown {
        width: card.contentWidth
        model: root.displayOptions
        currentIndex: root.displayIndex
        onActivated: function (index) { root.chooseDisplay(index) }
      }

      Dropdown {
        width: card.contentWidth
        visible: NotificationHost.displayMode === "specific"
        model: root.screenOptions
        currentIndex: root.screenIndex
        onActivated: function (index) { root.chooseScreen(index) }
      }

      Toggle {
        width: card.contentWidth
        label: "Step aside over fullscreen"
        description: "Leave the popup surface unmapped when a fullscreen window has nothing to announce."
        checked: NotificationHost.fullscreenStepAside
        onToggled: NotificationHost.setFullscreenStepAside(!NotificationHost.fullscreenStepAside)
      }

      Toggle {
        width: card.contentWidth
        label: "Offer snooze while sharing"
        description: "Suggest a timed snooze when a portal screen share starts."
        checked: NotificationHost.offerSnoozeWhenSharing
        onToggled: NotificationHost.setOfferSnoozeWhenSharing(!NotificationHost.offerSnoozeWhenSharing)
      }

      Text {
        width: parent.width
        height: implicitHeight
        text: "Keep history for"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Dropdown {
        width: card.contentWidth
        model: root.retentionOptions
        currentIndex: root.retentionIndex
        onActivated: function (index) { root.chooseRetention(index) }
      }


      Toggle {
        width: card.contentWidth
        label: "Let codes through"
        description: "Verification codes still appear while notifications are quiet."
        checked: NotificationHost.codesBypassQuiet
        onToggled: NotificationHost.setCodesBypass(!NotificationHost.codesBypassQuiet)
      }
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