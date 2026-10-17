import QtQuick
import ".."
import "."

// The password prompt a privilege request raises: a scrim over everything with
// a card in the middle. Its window lives in shell.qml, since a privilege
// request belongs to no bar module.
//
// The scrim takes clicks so nothing underneath is reachable while it is up,
// which is what makes this modal without a window manager to ask.
Item {
  id: root

  property string message: ""
  property string prompt: ""
  property string detail: ""
  property bool detailIsError: false

  signal submitted(string value)
  signal cancelled()

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)

    MouseArea {
      anchors.fill: parent
    }
  }

  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(Style.space(380), parent.width - Style.space(48))
    height: column.implicitHeight + Style.space(24) * 2
    color: Theme.surface
    border.width: 1
    border.color: root.detailIsError ? Theme.danger : Theme.muted
    radius: Theme.cornerRadius

    Column {
      id: column

      anchors.fill: parent
      anchors.margins: Style.space(24)
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: root.message !== "" ? root.message : "Authentication required"
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.detail !== ""
        text: root.detail
        color: root.detailIsError ? Theme.danger : Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      // A label rather than the field's placeholder: Qt masks the placeholder
      // too when echoMode is Password, so the prompt arrived as a row of dots.
      Text {
        width: parent.width
        visible: root.prompt !== ""
        text: root.prompt
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      // A bare TextInput rather than the Controls TextField: that one supplies a
      // dotted placeholder of its own for a password field, which reads as
      // though a password were already in it. TextInput has no placeholder at
      // all, and the prompt is already spelled out above.
      Rectangle {
        width: parent.width
        height: Style.space(30)
        color: Theme.bg
        border.width: 1
        border.color: password.activeFocus ? Theme.primary : Theme.muted
        radius: Theme.cornerRadius

        TextInput {
          id: password

          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          selectByMouse: true
          clip: true

          onAccepted: root.submitted(password.text)
        }
      }

      Row {
        anchors.right: parent.right
        spacing: Style.space(8)

        WidgetButton {
          text: "Cancel"
          fontSize: Style.font.body
          centerFigures: false
          onPressed: function () { root.cancelled() }
        }

        WidgetButton {
          text: "Authenticate"
          fontSize: Style.font.body
          centerFigures: false
          useActiveColor: false
          onPressed: function () { root.submitted(password.text) }
        }
      }
    }
  }

  // Cleared on every appearance so a previous attempt's password is never left
  // sitting in the field, and focused straight away so typing works at once.
  onVisibleChanged: {
    if (!visible) return
    password.text = ""
    password.forceActiveFocus()
  }

  Component.onCompleted: password.forceActiveFocus()
}
