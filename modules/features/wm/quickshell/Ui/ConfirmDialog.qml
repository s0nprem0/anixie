import QtQuick
import ".."

// A yes/no card, for the actions that lose something: pruning snapshots, dropping
// a wallpaper, restoring over /home.
//
// Deliberately a Popup and not a plain item: a confirmation that can be missed,
// or that a click elsewhere walks past, is not a confirmation. This one takes the
// keyboard while it is up, draws above whatever opened it, and only closes on a
// deliberate choice — the buttons or Escape. The outside click does nothing.
//
// The caller owns the wording and what running means, and gives the dialog the
// panel's box so the scrim covers it:
//
//   id: dlg
//   anchors.fill: parent
//   onConfirmed: root.dropTheThing()
//
// It opens with `open()` and closes itself on a button or Escape.
Item {
  id: root

  property string text: ""
  property string confirmText: "Confirm"
  property string cancelText: "Cancel"
  property string detail: ""
  property bool danger: false

  signal confirmed()
  signal cancelled()

  visible: false

  function open() {
    root.visible = true
    card.forceActiveFocus()
  }

  function close() {
    root.visible = false
  }

  implicitWidth: 0
  implicitHeight: 0

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
  }

  Rectangle {
    id: card
    width: Style.space(340)
    height: cardColumn.implicitHeight + Style.space(20) * 2
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: root.danger ? Theme.danger : Theme.muted
    border.width: 1
    anchors.centerIn: parent
    focus: true
    Keys.onEscapePressed: {
      root.cancelled()
      root.close()
    }

    Column {
      id: cardColumn
      anchors.centerIn: parent
      width: card.width - Style.space(20) * 2
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: root.text
        color: Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Text {
        width: parent.width
        visible: root.detail !== ""
        text: root.detail
        color: Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
      }

      Item {
        width: parent.width
        height: Style.space(28)

        ConfirmButton {
          id: confirmButton
          anchors.right: parent.right
          width: confirmButton.label.implicitWidth + Style.space(24)
          height: parent.height
          label: root.confirmText
          danger: root.danger
          onClicked: {
            root.confirmed()
            root.close()
          }
        }

        ConfirmButton {
          anchors.right: confirmButton.left
          anchors.rightMargin: Style.space(8)
          width: cancelButton.label.implicitWidth + Style.space(24)
          height: parent.height
          onClicked: {
            root.cancelled()
            root.close()
          }

          Text {
            id: cancelButton
            anchors.centerIn: parent
            text: root.cancelText
            color: Theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }

  component ConfirmButton: Item {
    id: button
    property alias label: buttonLabel
    property bool danger: false

    signal clicked()

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: button.danger
        ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, mouse.containsMouse ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
        : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, mouse.containsMouse ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
      Behavior on color { NumberAnimation { duration: Style.duration(120) } }
    }

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      color: button.danger ? Theme.danger : Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }
}