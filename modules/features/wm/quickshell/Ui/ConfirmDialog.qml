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

  // Seconds before the dialog gives up and reports `timedOut`. Zero is a plain
  // yes/no that waits for an answer; the display panel uses this for a change
  // that must be confirmed before it becomes permanent.
  property int countdown: 0
  property int remaining: 0

  signal confirmed()
  signal cancelled()
  signal timedOut()

  visible: false

  // The control that had the keyboard before the dialog took it. Restored after
  // closing, so cancelling a confirmation does not leave the panel deaf to the
  // arrow keys that were working a moment ago.
  property Item previousFocus: null

  function open() {
    const win = root.Window && root.Window.window ? root.Window.window : null
    root.previousFocus = win ? win.activeFocusItem : null
    root.visible = true
    root.remaining = root.countdown
    if (root.countdown > 0) countdownTimer.restart()
    card.forceActiveFocus()
  }

  function close() {
    countdownTimer.stop()
    root.visible = false
    const target = root.previousFocus
    root.previousFocus = null
    if (!target) return
    // After the dialog is hidden, not before: making the focused card invisible
    // moves the active focus itself, and would undo a restore done here.
    Qt.callLater(function () {
      if (target && target.visible) target.forceActiveFocus()
    })
  }

  implicitWidth: 0
  implicitHeight: 0

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    running: root.visible && root.countdown > 0
    onTriggered: {
      root.remaining -= 1
      if (root.remaining <= 0) {
        root.timedOut()
        root.close()
      }
    }
  }

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Theme.curtain

    // A scrim that only paints is not a scrim: without a handler the click
    // falls through to the panel underneath and hits whatever row was behind
    // the confirmation. Accept the click and do nothing with it.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }
  }

  Rectangle {
    id: card
    // A confirmation belongs to the panel that opened it, and the session panel
    // is narrower than the dialog's preferred width. Cap it to the box instead
    // of letting it hang over the screen edge.
    width: Math.min(Style.space(340), parent.width - Style.space(20))
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

    // The card's own background has no controls, but a click on it must not
    // reach the row underneath. The buttons are declared after this area, so
    // they stay on top and keep their own clicks.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
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

      Text {
        width: parent.width
        visible: root.countdown > 0
        text: "Reverting in " + Math.max(0, root.remaining) + "s"
        color: root.danger ? Theme.danger : Theme.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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