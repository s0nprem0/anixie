import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."
import "."
import "NotificationText.js" as NotificationText

// One notification: sender and icon, summary, body, and any actions the sender
// offered. Clicking the card dismisses it.
Item {
  id: root

  property var notification: null

  // The notifications this card belongs to. The popup passes one per card now;
  // the property is kept so a future deck can group them without changing the
  // card's click behaviour.
  property var group: []

  // A replayed history entry looks like a card but has no live client behind it.
  // Clicking it removes just that card instead of dismissing a notification the
  // daemon no longer owns.
  property bool replay: false

  // A card in the history panel is a persistent view: it stays until the user
  // closes it, rather than vanishing while it is being read. Popup cards keep
  // the normal sender timeout.
  property bool autoExpire: true

  readonly property string appName: root.notification
    ? String(root.notification.appName || root.notification.app || "").slice(0, 256)
    : ""
  readonly property string sourceLabel: NotificationText.source(root.notification) || root.appName
  readonly property string sourceKey: NotificationText.sourceKey(root.notification) || root.appName.toLowerCase()
  readonly property string appLabel: root.group.length > 1
    ? root.sourceLabel + "  ·  " + root.group.length
    : root.sourceLabel
  readonly property string summary: root.notification ? String(root.notification.summary || "").slice(0, 2048) : ""
  readonly property string body: root.notification ? String(root.notification.body || "").slice(0, 32768) : ""
  readonly property string image: root.notification ? String(root.notification.image || "") : ""
  readonly property string appIcon: root.notification ? String(root.notification.appIcon || "") : ""
  readonly property string initial: root.sourceLabel !== "" ? root.sourceLabel.substring(0, 1).toUpperCase() : ""

  // Live notifications carry no arrival time; the card records one so the age
  // beside the sender behaves like the history rows. Snapshot timestamps are
  // milliseconds, the same unit as Date.now().
  property double arrivedAt: Date.now()
  readonly property double stamp: root.notification && root.notification.timestamp !== undefined
    ? Number(root.notification.timestamp)
    : root.arrivedAt

  // Re-evaluates the age while the card is on screen. A toast can stay up for
  // half a minute; a clock that never moves reads as frozen.
  property int nowTick: 0

  function ago() {
    if (!root.stamp) return ""
    const now = Date.now() + (root.nowTick * 0)
    const seconds = Math.max(0, Math.floor((now - root.stamp) / 1000))
    if (seconds < 300) return ""
    if (seconds < 3600) return Math.round(seconds / 60) + "m ago"
    const date = new Date(root.stamp)
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }

  // A sender using `notify` can carry a glyph and a command as hints. The live
  // object exposes them in `hints`; a history entry keeps them as fields, since
  // a replayed notification has no sender left to ask.
  function hint(name, field) {
    if (!root.notification) return ""

    const stored = root.notification[field]
    if (stored !== undefined) return String(stored || "")

    const hints = root.notification.hints
    return hints && hints[name] !== undefined ? String(hints[name]) : ""
  }

  readonly property string glyph: root.hint("anixie-glyph", "glyph")
  readonly property var execArgv: {
    const raw = root.hint("anixie-exec", "execArgv")
    return NotificationText.execArgv(raw)
  }
  readonly property string link: NotificationText.link(root.summary + "\n" + root.body)
  readonly property var codes: NotificationText.codes(root.summary + "\n" + root.body)
  readonly property string displayBody: NotificationText.displayBody(root.notification)

  // The icon theme is not guaranteed to be ready on the first frame. The
  // binding reads this tick so a card that arrived early resolves its site icon
  // once the theme is available instead of keeping the letter fallback forever.
  property int iconTick: 0

  function siteIcon() {
    const tick = root.iconTick
    if (!NotificationText.isBrowser(root.appName)) return ""
    const names = [root.sourceLabel]
    const brands = NotificationText.brands(root.sourceLabel)
    for (let i = 0; i < brands.length; i++) names.push(brands[i])
    for (let i = 0; i < names.length; i++) {
      const found = Quickshell.iconPath(names[i], true)
      if (found !== "") return found
    }
    return ""
  }

  readonly property string imageSource: {
    const tick = root.iconTick
    if (root.image !== "") {
      if (root.image.indexOf("image://qsimage/") === 0) return root.image
      const local = NotificationText.localImagePath(root.image)
      if (local !== "") return "file://" + local
      // An image the policy rejected is not the end of the card's icon: fall
      // through to the site or app icon rather than leaving a blank slot.
    }

    const site = root.siteIcon()
    if (site !== "") return site

    if (root.appIcon === "") return ""
    if (root.appIcon.indexOf("/") === 0) {
      const path = NotificationText.localImagePath(root.appIcon)
      return path === "" ? "" : "file://" + path
    }
    if (root.appIcon.indexOf("file://") === 0) {
      const path = NotificationText.localImagePath(root.appIcon)
      return path === "" ? "" : "file://" + path
    }
    if (root.appIcon.indexOf("image://icon/") === 0) {
      const name = root.appIcon.slice("image://icon/".length).split("?")[0]
      return Quickshell.iconPath(name, true)
    }
    if (root.appIcon.indexOf("image://") === 0) return ""
    return Quickshell.iconPath(root.appIcon, true)
  }

  readonly property bool critical: root.notification
    ? root.notification.urgency === NotificationUrgency.Critical
    : false
  // The protocol's default action — the one a click on the body should run — is
  // not a property in this Quickshell, only an entry in the action list with the
  // identifier "default". It is pulled out here so the click can honour it and
  // the buttons can show the actions the sender actually labelled.
  readonly property var defaultAction: {
    if (!root.notification || !root.notification.actions) return null
    for (const action of root.notification.actions) {
      if (String(action.identifier) === "default") return action
    }
    return null
  }

  readonly property int maxActions: 16
  readonly property int maxActionLabel: 256

  readonly property var actions: {
    const out = []
    if (!root.notification || !root.notification.actions) return out
    for (const action of root.notification.actions) {
      if (out.length >= root.maxActions) break
      // "default" has no button: it is the body, and a sender that offers it
      // usually leaves its text empty, which drew an empty button.
      if (String(action.identifier) === "default") continue
      const label = String(action.text || "").slice(0, root.maxActionLabel)
      if (label === "") continue
      out.push({ text: label, invoke: function () { action.invoke() } })
    }
    return out
  }

  // How long a toast stays, by urgency: a low notification is a glance, a
  // normal one is long enough to read, and a critical one stays until it is
  // dismissed. A failing battery or an alarm should not disappear while nobody
  // is looking at the screen.
  readonly property int lowSeconds: 5
  readonly property int normalSeconds: 8
  readonly property int senderCeilingSeconds: 30

  readonly property real displaySeconds: {
    if (!root.notification) return 0
    if (root.notification.urgency === NotificationUrgency.Critical) return 0

    // `resident` deliberately does NOT appear here. The protocol defines it as
    // "do not remove the notification when an action is invoked" — it is about
    // what happens after a click, not about how long the toast lives. Reading it
    // as a lifetime is what left resident notifications from chat clients
    // stacking up on screen indefinitely, with no way to clear them but clicking
    // each one.
    const base = root.notification.urgency === NotificationUrgency.Low
      ? root.lowSeconds
      : root.normalSeconds
    const timeout = root.notification.expireTimeout

    // A sender asking for longer is honoured, up to a point: an hour-long `-t`
    // pins one card on screen and pushes everything after it away, and senders
    // that ask for that usually expect the server to bound it. A zero or
    // negative timeout means "no preference", so the urgency's own default
    // stands.
    return timeout > 0 ? Math.min(Math.max(base, timeout), root.senderCeilingSeconds) : base
  }

  // The countdown, pausable. A toast that vanishes while it is being read is
  // worse than one that waits, so hovering stops it and leaving starts it again
  // from the time that was left rather than from the top.
  property int remainingMs: 0

  function armExpiry() {
    expiry.stop()
    root.remainingMs = Math.round(root.displaySeconds * 1000)

    if (root.replay || !root.autoExpire || root.displaySeconds <= 0 || hover.hovered) return

    expiry.interval = root.remainingMs
    expiry.start()
  }

  function pauseExpiry() {
    if (!expiry.running) return

    // One millisecond rather than zero: a timer caught on its last tick should
    // still be resumable, and a zero interval would fire the moment it starts.
    root.remainingMs = Math.max(1, expiry.remaining)
    expiry.stop()
  }

  function resumeExpiry() {
    if (root.replay || root.displaySeconds <= 0 || root.remainingMs <= 0) return

    expiry.interval = root.remainingMs
    expiry.start()
  }

  Component.onCompleted: root.armExpiry()
  onNotificationChanged: {
    root.arrivedAt = Date.now()
    root.armExpiry()
  }
  onDisplaySecondsChanged: root.armExpiry()
  onReplayChanged: root.armExpiry()
  onAutoExpireChanged: root.armExpiry()

  HoverHandler {
    id: hover

    onHoveredChanged: hover.hovered ? root.pauseExpiry() : root.resumeExpiry()
  }

  implicitWidth: Style.space(380)
  implicitHeight: card.implicitHeight

  // Put the card away without running anything. A right-click is an explicit
  // dismissal — including a resident notification, which only promises to
  // survive an *action* — and a replayed row is not a live notification at all.
  function dismissCard() {
    if (root.replay) {
      NotificationHost.dismissReplay(root.notification)
      return
    }

    if (root.group.length > 0) {
      for (const item of root.group) item.dismiss()
    } else if (root.notification) {
      root.notification.dismiss()
    }
  }

  // The same action a left click on the card takes. Kept as a function so the
  // panel's keyboard walk can run it with Return.
  function activateCard() {
    if (root.replay) {
      if (root.execArgv) Quickshell.execDetached(root.execArgv)
      else if (root.link !== "") Quickshell.execDetached(["xdg-open", root.link])
      else NotificationHost.activate(root.notification, "")
      NotificationHost.dismissReplay(root.notification)
      return
    }

    const action = root.defaultAction
    if (root.execArgv) {
      Quickshell.execDetached(root.execArgv)
    } else if (action) {
      action.invoke()
    } else {
      NotificationHost.activate(root.notification, root.link)
    }

    // Resident means "do not remove me when an action is invoked"; it says
    // nothing about a plain dismissal click. So a resident notification
    // survives a protocol action — the action buttons below already honour
    // that — but the same click with nothing to run still puts it away. An
    // attached command is data, not a resident sender's action, so it does not
    // keep the card around.
    const keepResident = !root.execArgv && action !== null
    if (root.group.length > 0) {
      for (const item of root.group) if (!(keepResident && item.resident)) item.dismiss()
    } else if (root.notification && !(keepResident && root.notification.resident)) {
      root.notification.dismiss()
    }
  }

  // Only the copies drawn inside the history panel are walked by Panel.qml;
  // toasts live in their own window and take no keyboard.
  readonly property bool panelFocusable: true
  function activate() { root.activateCard() }
  function keyStep(direction) { return false }

  // Declared first so it sits under everything: a click that no action button
  // claimed falls through to here and dismisses the notification.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    // A left click runs the sender's command (if any), else the protocol's
    // default action, else takes you to the window that sent it. A group goes
    // together: one click on a stack of five puts five away. A right-click never
    // runs anything; it only dismisses.
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton) root.dismissCard()
      else root.activateCard()
    }
  }

  Rectangle {
    id: card

    anchors.fill: parent
    color: Theme.surface
    border.width: Style.strokeWidth
    border.color: root.critical ? Theme.danger : (root.replay ? Theme.accent : Theme.border)
    radius: Theme.cornerRadius

    implicitHeight: content.implicitHeight + Style.space(20)

    Row {
      id: content

      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(10)

      Image {
        width: Style.space(40)
        height: Style.space(40)
        source: root.imageSource
        visible: root.imageSource !== ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      // A glyph only stands in for the icon slot when there is no image or
      // themed icon to show. The sender decides the glyph; the card only draws
      // it, so a Nerd Font character never has to be written into a QML file.
      Text {
        width: Style.space(40)
        height: Style.space(40)
        visible: root.imageSource === "" && root.glyph !== ""
        text: root.glyph
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
      }

      // A sender with no image and no glyph still gets a mark rather than a
      // blank slot: the first letter is the same fallback the dock uses.
      Text {
        width: Style.space(40)
        height: Style.space(40)
        visible: root.imageSource === "" && root.glyph === "" && root.initial !== ""
        text: root.initial
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
      }

      Column {
        width: content.width - Style.space(40) - Style.space(10)
        spacing: Style.space(3)

        // Sender and age sit above the message, where the eye looks for
        // provenance before reading a title. The width reserves the two hover
        // buttons so they never sit on top of the text.
        Text {
          width: Math.max(0, parent.width - Style.space(44))
          text: (root.appLabel !== "" ? root.appLabel : "Notification")
            + (root.ago() !== "" ? "  ·  " + root.ago() : "")
          textFormat: Text.PlainText
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: NotificationText.plain(root.summary)
          textFormat: Text.PlainText
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: root.displayBody !== ""
          text: NotificationText.rich(root.displayBody)
          textFormat: Text.RichText
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: hover.hovered ? 8 : 3
          elide: Text.ElideRight
          onLinkActivated: function (link) {
            const safe = NotificationText.safeUrl(link)
            if (safe !== "") Quickshell.execDetached(["xdg-open", safe])
          }
        }

        // Code detection and the sender's actions in one row: both are things
        // the card can do, and both should be visible without hunting through a
        // menu. The code is copied sensitive so it does not enter clipboard
        // history.
        Row {
          width: parent.width
          visible: root.actions.length > 0 || root.codes.length > 0
          spacing: Style.space(6)

          WidgetButton {
            visible: root.codes.length > 0
            text: "Copy code"
            fontSize: Style.font.bodySmall
            centerFigures: false
            useActiveColor: false
            onPressed: function () {
              if (root.codes.length === 0) return
              Quickshell.execDetached(["wl-copy", "--sensitive", "--", String(root.codes[0])])
            }
          }

          Repeater {
            model: root.actions

            delegate: WidgetButton {
              id: actionButton
              required property var modelData

              text: String(actionButton.modelData.text || "")
              fontSize: Style.font.bodySmall
              centerFigures: false
              useActiveColor: false

              onPressed: function () {
                actionButton.modelData.invoke()
                // A resident notification outlives its actions by definition:
                // that is the whole point of the hint, and dismissing it here
                // would make the sender's request pointless.
                if (root.notification && !root.notification.resident) root.notification.dismiss()
              }
            }
          }
        }
      }
    }
  }

  // A snooze is a quiet with an end time. It sits beside close and only appears
  // with the pointer, so the card stays readable until someone reaches for it.
  function openSnoozeMenu(anchor) {
    const entries = []
    const options = NotificationHost.snoozeOptions()
    for (let i = 0; i < options.length; i++) {
      const option = options[i]
      entries.push({
        label: option.label,
        glyph: Util.clock,
        action: function () { NotificationHost.snooze(root.sourceKey, option.seconds) }
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

  // The close button appears with the pointer, the way the reference's does: a
  // toast is read, not operated, so nothing permanent is drawn over the text.
  // It sits above the dismissal MouseArea and takes its own clicks, so pressing
  // it dismisses without also running the sender's default action.
  Item {
    id: snoozeButton

    anchors.top: parent.top
    anchors.right: closeButton.left
    anchors.topMargin: Style.space(4)
    anchors.rightMargin: Style.space(2)
    width: Style.space(18)
    height: Style.space(18)

    opacity: hover.hovered || snoozeArea.containsMouse ? 1 : 0
    visible: opacity > 0
    readonly property bool tooltipHovered: snoozeArea.containsMouse

    Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
        snoozeArea.containsMouse ? Style.control.hoverFillAlpha : 0.08)
    }

    Text {
      anchors.centerIn: parent
      text: Util.clock
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: snoozeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openSnoozeMenu(snoozeButton)
      onEntered: TooltipHost.show("Snooze " + root.sourceLabel, snoozeButton)
      onExited: TooltipHost.hide(snoozeButton)
    }
  }

  Item {
    id: closeButton

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(4)
    width: Style.space(18)
    height: Style.space(18)

    opacity: hover.hovered || closeArea.containsMouse ? 1 : 0
    visible: opacity > 0
    readonly property bool tooltipHovered: closeArea.containsMouse

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(120) }
    }

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
        closeArea.containsMouse ? Style.control.hoverFillAlpha : 0.08)
    }

    Text {
      anchors.centerIn: parent
      text: Util.close
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.dismissCard()
      onEntered: TooltipHost.show("Dismiss", closeButton)
      onExited: TooltipHost.hide(closeButton)
    }
  }

  Timer {
    id: expiry
    repeat: false
    onTriggered: if (root.notification) root.notification.expire()
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowTick++
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.iconTick++
  }
}
