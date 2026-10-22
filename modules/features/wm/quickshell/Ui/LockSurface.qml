import QtQuick
import ".."
import "."

// One screen of the session lock. WlSessionLock creates one of these per output
// and the compositor routes input only to the locked session, so this is the
// whole of what the user can reach until authentication succeeds.
Item {
  id: root

  focus: true

  property var now: new Date()
  readonly property string timeText: Qt.formatTime(root.now, "HH:mm")
  readonly property string dateText: Qt.formatDate(root.now, "dddd, d MMMM")

  readonly property string fingerprintHint: {
    if (LockHost.fingerprintUnavailable) return "Fingerprint unavailable — use your password."
    if (LockHost.fingerprintTrying) return "Touch the fingerprint reader"
    if (LockHost.fingerprintFailures > 0) return "Not recognized — try again or type your password."
    return "Touch the fingerprint reader to unlock"
  }

  function imageUrl(path) {
    if (!path) return ""
    return path.indexOf("/") === 0 ? "file://" + path : path
  }

  Component.onCompleted: Qt.callLater(function () { password.forceActiveFocus() })

  AnimatedImage {
    anchors.fill: parent
    source: root.imageUrl(BackgroundHost.path)
    sourceSize.width: width
    sourceSize.height: height
    fillMode: AnimatedImage.PreserveAspectCrop
    smooth: true
    cache: false
    asynchronous: true
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.58)
  }

  // Empty areas focus the field; the field itself sits above this and takes its
  // own clicks, so a click on the password box does not get swallowed here.
  MouseArea {
    anchors.fill: parent
    onClicked: password.forceActiveFocus()
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: root.timeText
      color: Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.space(52)
      font.weight: Font.Light
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: implicitHeight
      text: root.dateText
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    Item { width: 1; height: Style.space(18) }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: inner.width + Style.space(28) * 2
      height: inner.implicitHeight + Style.space(20) * 2
      radius: Theme.cornerRadius
      color: Theme.surface
      border.width: 1
      border.color: Theme.muted

      Column {
        id: inner

        anchors.centerIn: parent
        width: Style.space(260)
        spacing: Style.space(8)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          height: implicitHeight
          spacing: Style.space(6)

          Text {
            height: implicitHeight
            text: Util.lock
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            height: implicitHeight
            text: LockHost.userName
            color: Theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        TextField {
          id: password

          width: parent.width
          height: implicitHeight
          echoMode: TextInput.Password
          placeholderText: "Password"
          horizontalAlignment: TextInput.AlignHCenter
          enabled: !LockHost.authenticatingPassword && !LockHost.lockedOut

          onAccepted: {
            const value = password.text
            password.text = ""
            LockHost.submitPassword(value)
          }

          onTextChanged: if (password.text.length > 0) LockHost.clearFailure()

          Keys.onPressed: function (event) {
            if (event.key !== Qt.Key_Escape) return
            password.text = ""
            LockHost.clearFailure()
            event.accepted = true
          }
        }

        Item {
          width: fpRow.implicitWidth
          height: fpRow.implicitHeight
          anchors.horizontalCenter: parent.horizontalCenter
          visible: LockHost.fingerprintConfigured

          Row {
            id: fpRow

            spacing: Style.space(6)

            Text {
              height: implicitHeight
              text: Util.fingerprint
              color: LockHost.fingerprintUnavailable
                ? Theme.danger
                : (LockHost.fingerprintTrying ? Theme.primary : Theme.muted)
              font.family: Style.font.family
              font.pixelSize: Style.space(16)
            }

            Text {
              height: implicitHeight
              text: root.fingerprintHint
              color: LockHost.fingerprintUnavailable ? Theme.danger : Theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: LockHost.retryFingerprint()
          }
        }

        Text {
          width: parent.width
          height: implicitHeight
          visible: LockHost.authenticatingPassword
          text: "Checking…"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          height: implicitHeight
          visible: LockHost.failure !== "" && !LockHost.authenticatingPassword
          text: LockHost.failure
          color: Theme.danger
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }

  Connections {
    target: LockHost
    function onRequestedChanged() {
      if (LockHost.requested) Qt.callLater(function () { password.forceActiveFocus() })
    }
  }
}
