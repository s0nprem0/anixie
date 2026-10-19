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

    // The shell is keyboard-first everywhere else; a dialog that needs a pointer
    // is the one place that would break the habit.
    Keys.onReturnPressed: {
      root.confirmed()
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
          width: confirmButton.implicitWidth
          height: parent.height
          label: root.confirmText
          danger: root.danger
          onClicked: {
            root.confirmed()
            root.close()
          }
        }

        ConfirmButton {
          id: cancelButton
          anchors.right: confirmButton.left
          anchors.rightMargin: Style.space(8)
          width: implicitWidth
          height: parent.height
          label: root.cancelText
          onClicked: {
            root.cancelled()
            root.close()
          }
        }
      }
    }
  }

  component ConfirmButton: Item {
    id: button
    // A plain property, not an alias: the alias pointed at the Text and was
    // read-only, so every caller's `label:` failed the moment this file was used.
    property string label: ""
    property bool danger: false

    // Sized by its own label, so a caller does not have to reach into the Text.
    implicitWidth: labelText.implicitWidth + Style.space(24)
    implicitHeight: Style.space(28)

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
      id: labelText
      anchors.centerIn: parent
      text: button.label
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