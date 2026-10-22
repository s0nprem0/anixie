import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."
import "."

// One notification: sender and icon, summary, body, and any actions the sender
// offered. Clicking the card dismisses it.
Item {
  id: root

  property var notification: null

  // The rest of the group, oldest included; one notification when it is alone.
  property var group: []

  // A replayed history entry looks like a card but has no live client behind it.
  // Clicking it removes just that card instead of dismissing a notification the
  // daemon no longer owns.
  property bool replay: false

  readonly property string appName: {
    if (!root.notification) return ""
    // Live notifications expose appName; history snapshots store the same
    // value as `app`, so replayed cards read either.
    const name = String(root.notification.appName || root.notification.app || "")
    // The count rides on the app name rather than a badge of its own: it is the
    // same fact — who this is from, and how much of it there is — and it needs no
    // new geometry in a card laid out by hand.
    return root.group.length > 1 ? name + "  ·  " + root.group.length : name
  }
  readonly property string summary: root.notification ? String(root.notification.summary || "") : ""
  readonly property string body: root.notification ? String(root.notification.body || "") : ""
  readonly property string image: root.notification ? String(root.notification.image || "") : ""
  readonly property string appIcon: root.notification ? String(root.notification.appIcon || "") : ""

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
  readonly property string exec: root.hint("anixie-exec", "exec")

  readonly property string imageSource: root.image !== ""
    ? (root.image.indexOf("/") === 0 ? "file://" + root.image : root.image)
    : (root.appIcon !== "" ? Quickshell.iconPath(root.appIcon, "") : "")

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

  readonly property var actions: {
    const out = []
    if (!root.notification || !root.notification.actions) return out
    for (const action of root.notification.actions) {
      // "default" has no button: it is the body, and a sender that offers it
      // usually leaves its text empty, which drew an empty button.
      if (String(action.identifier) === "default") continue
      if (String(action.text || "") === "") continue
      out.push(action)
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

    if (root.replay || root.displaySeconds <= 0 || hover.hovered) return

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
  onDisplaySecondsChanged: root.armExpiry()
  onReplayChanged: root.armExpiry()

  HoverHandler {
    id: hover

    onHoveredChanged: hover.hovered ? root.pauseExpiry() : root.resumeExpiry()
  }

  implicitWidth: Style.space(340)
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

  // Declared first so it sits under everything: a click that no action button
  // claimed falls through to here and dismisses the notification.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    // A left click runs the command the sender attached (if any), else the
    // protocol's default action, then puts the card away — clicking a message
    // opens it, it does not merely hide it. A group goes together: one click on a
    // stack of five puts five away. A right-click never runs anything; it only
    // dismisses.
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton) {
        root.dismissCard()
        return
      }

      if (root.replay) {
        if (root.exec !== "") Quickshell.execDetached(["sh", "-c", root.exec])
        NotificationHost.dismissReplay(root.notification)
        return
      }

      const action = root.defaultAction
      if (root.exec !== "") {
        Quickshell.execDetached(["sh", "-c", root.exec])
      } else if (action) {
        action.invoke()
      }

      // Resident means "do not remove me when an action is invoked"; it says
      // nothing about a plain dismissal click. So a resident notification
      // survives a protocol action — the action buttons below already honour
      // that — but the same click with nothing to run still puts it away. An
      // attached command is data, not a resident sender's action, so it does not
      // keep the card around.
      const keepResident = root.exec === "" && action !== null
      if (root.group.length > 0) {
        for (const item of root.group) if (!(keepResident && item.resident)) item.dismiss()
      } else if (root.notification && !(keepResident && root.notification.resident)) {
        root.notification.dismiss()
      }
    }
  }

  Rectangle {
    id: card

    anchors.fill: parent
    color: Theme.surface
    border.width: 1
    border.color: root.critical ? Theme.danger : (root.replay ? Theme.accent : Theme.muted)
    radius: Theme.cornerRadius

    implicitHeight: content.implicitHeight + Style.space(20)

    Row {
      id: content

      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(10)

      Image {
        width: Style.space(24)
        height: Style.space(24)
        source: root.imageSource
        visible: root.imageSource !== ""
        sourceSize.width: Style.bar.iconSize * 2
        sourceSize.height: Style.bar.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      // A glyph only stands in for the icon slot when there is no image or
      // themed icon to show. The sender decides the glyph; the card only draws
      // it, so a Nerd Font character never has to be written into a QML file.
      Text {
        width: Style.space(24)
        height: Style.space(24)
        visible: root.imageSource === "" && root.glyph !== ""
        text: root.glyph
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.space(17)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
      }

      Column {
        width: content.width - Style.space(24) - Style.space(10)
        spacing: Style.space(3)

        Text {
          width: parent.width
          text: root.summary
          textFormat: Text.PlainText
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: root.body !== ""
          text: root.body
          textFormat: Text.PlainText
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: root.appName !== ""
          text: root.appName
          textFormat: Text.PlainText
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // Only the actions the sender actually offered, in its order.
        Row {
          width: parent.width
          visible: root.actions.length > 0
          spacing: Style.space(6)

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

  // The close button appears with the pointer, the way the reference's does: a
  // toast is read, not operated, so nothing permanent is drawn over the text.
  // It sits above the dismissal MouseArea and takes its own clicks, so pressing
  // it dismisses without also running the sender's default action.
  Item {
    id: closeButton

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(4)
    width: Style.space(18)
    height: Style.space(18)

    opacity: hover.hovered || closeArea.containsMouse ? 1 : 0
    visible: opacity > 0

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
      onClicked: root.dismissCard()
    }
  }

  Timer {
    id: expiry
    repeat: false
    onTriggered: if (root.notification) root.notification.expire()
  }
}
