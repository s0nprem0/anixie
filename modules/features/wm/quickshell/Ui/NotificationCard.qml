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

  readonly property string appName: root.notification ? String(root.notification.appName || "") : ""
  readonly property string summary: root.notification ? String(root.notification.summary || "") : ""
  readonly property string body: root.notification ? String(root.notification.body || "") : ""
  readonly property string image: root.notification ? String(root.notification.image || "") : ""
  readonly property string appIcon: root.notification ? String(root.notification.appIcon || "") : ""
  readonly property bool critical: root.notification
    ? root.notification.urgency === NotificationUrgency.Critical
    : false
  readonly property var actions: root.notification && root.notification.actions ? root.notification.actions : []

  // What the sender can ask for, as the protocol defines it: a positive timeout
  // is seconds, zero means hold it until dismissed, and a negative one asks the
  // server for its own default. Collapsing the last two would leave anything
  // sent without an explicit timeout on screen forever.
  readonly property int serverDefaultSeconds: 5

  readonly property real displaySeconds: {
    if (!root.notification || root.notification.resident) return 0

    const timeout = root.notification.expireTimeout
    if (timeout > 0) return timeout
    if (timeout === 0) return 0
    return root.serverDefaultSeconds
  }

  implicitWidth: Style.space(340)
  implicitHeight: card.implicitHeight

  // Declared first so it sits under everything: a click that no action button
  // claimed falls through to here and dismisses the notification.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: if (root.notification) root.notification.dismiss()
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
                if (root.notification) root.notification.dismiss()
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
