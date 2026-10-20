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

  readonly property string appName: {
    if (!root.notification) return ""
    const name = String(root.notification.appName || "")
    // The count rides on the app name rather than a badge of its own: it is the
    // same fact — who this is from, and how much of it there is — and it needs no
    // new geometry in a card laid out by hand.
    return root.group.length > 1 ? name + "  ·  " + root.group.length : name
  }
  readonly property string summary: root.notification ? String(root.notification.summary || "") : ""
  readonly property string body: root.notification ? String(root.notification.body || "") : ""
  readonly property string image: root.notification ? String(root.notification.image || "") : ""
  readonly property string appIcon: root.notification ? String(root.notification.appIcon || "") : ""
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

  // What the sender can ask for, as the protocol defines it: a positive timeout
  // is seconds, zero means the sender will not say, and a negative one asks the
  // server for its own default.
  readonly property int serverDefaultSeconds: 5

  readonly property real displaySeconds: {
    if (!root.notification) return 0

    // `resident` deliberately does NOT appear here. The protocol defines it as
    // "do not remove the notification when an action is invoked" — it is about
    // what happens after a click, not about how long the toast lives. Reading it
    // as a lifetime is what left resident notifications from chat clients
    // stacking up on screen indefinitely, with no way to clear them but clicking
    // each one.
    //
    // A zero timeout is taken as the server default rather than literally
    // forever, for the same reason: senders that pass 0 usually mean "no
    // preference", and taking it literally leaves a toast on screen with nothing
    // left to time it out.
    const timeout = root.notification.expireTimeout
    if (timeout > 0) return timeout
    return root.serverDefaultSeconds
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  // Declared first so it sits under everything: a click that no action button
  // claimed falls through to here and dismisses the notification.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    // A click runs the default action if the sender offered one, then puts the
    // card away — clicking a message opens it, it does not merely hide it. A
    // group goes together: one click on a stack of five puts five away.
    onClicked: {
      const action = root.defaultAction
      if (action) action.invoke()

      // Resident means "do not remove me when an action is invoked"; it says
      // nothing about a plain dismissal click. So a resident notification
      // survives a click that ran its action — the action buttons below already
      // honour that — but the same click with nothing to run still puts it away.
      const keepResident = action !== null
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
    border.color: root.critical ? Theme.danger : Theme.muted
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
        source: root.image !== ""
          ? (root.image.indexOf("/") === 0 ? "file://" + root.image : root.image)
          : (root.appIcon !== "" ? Quickshell.iconPath(root.appIcon, "") : "")
        sourceSize.width: Style.bar.iconSize * 2
        sourceSize.height: Style.bar.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
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

  Timer {
    interval: Math.round(root.displaySeconds * 1000)
    running: root.displaySeconds > 0
    onTriggered: if (root.notification) root.notification.expire()
  }
}
