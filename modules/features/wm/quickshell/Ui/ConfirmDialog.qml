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
// It opens with `open()` and closes itself on a button or Escape, or is closed
// by the caller after an asynchronous operation finishes.
Item {
  id: root
  objectName: "ConfirmDialog"

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

  // Operation state for asynchronous callers. `busy` prevents a second
  // confirmation from being submitted while one is already running; `errorText`
  // surfaces a failure without closing the dialog.
  property bool busy: false
  property string errorText: ""

  signal confirmed()
  signal cancelled()
  signal timedOut()

  // Internal open state. `visible` is derived so open/close can animate
  // opacity and scale without the item vanishing before the animation plays.
  property bool opened: false
  property bool closing: false
  visible: opened || closing

  opacity: closing ? 0 : (opened ? 1 : 0)
  scale: closing ? 0.96 : 1
  transformOrigin: Item.Center
  Behavior on opacity {
    NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
  }
  Behavior on scale {
    NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
  }

  implicitWidth: 0
  implicitHeight: 0

  // The control that had the keyboard before the dialog took it. Restored after
  // closing, so cancelling a confirmation does not leave the panel deaf to the
  // arrow keys that were working a moment ago.
  property Item previousFocus: null

  property double deadline: 0
  property bool _timedOutFired: false

  function open() {
    closeTimer.stop()
    if (!root.opened && !root.closing) {
      const win = root.Window && root.Window.window ? root.Window.window : null
      root.previousFocus = win ? win.activeFocusItem : null
    }
    root.closing = false
    root.opened = true
    root.busy = false
    root.errorText = ""
    root._timedOutFired = false
    if (root.countdown > 0) {
      root.deadline = Date.now() + root.countdown * 1000
      root.remaining = root.countdown
    } else {
      root.deadline = 0
      root.remaining = 0
    }
    Qt.callLater(function () {
      if (!root.opened) return
      if (root.danger) cancelButton.forceActiveFocus()
      else confirmButton.forceActiveFocus()
    })
  }

  function close() {
    if (!root.opened && !root.closing) return
    countdownTimer.stop()
    root.deadline = 0
    root._timedOutFired = false
    root.opened = false
    root.closing = true
    root.busy = false
    root.errorText = ""
    const target = root.previousFocus
    root.previousFocus = null
    if (target) {
      Qt.callLater(function () {
        try {
          if (target && target.visible && target.parent !== null)
            target.forceActiveFocus()
        } catch (e) {
        }
      })
    }
    closeTimer.restart()
  }

  Timer {
    id: countdownTimer
    interval: 250
    repeat: true
    running: root.opened && root.countdown > 0 && root.deadline > 0
    onTriggered: root._tick()
  }

  function _tick() {
    if (!root.opened) return
    const now = Date.now()
    const ms = root.deadline - now
    root.remaining = ms > 0 ? Math.ceil(ms / 1000) : 0
    if (ms <= 0) {
      if (!root._timedOutFired) {
        root._timedOutFired = true
        root.timedOut()
      }
      root.close()
    }
  }

  Timer {
    id: closeTimer
    interval: Math.max(1, Style.duration(Style.motion.fast))
    repeat: false
    onTriggered: root.closing = false
  }

  onParentChanged: {
    if (!root.parent && root.opened) root.close()
  }

  Connections {
    target: root.parent
    enabled: root.parent !== null
    function onVisibleChanged() {
      if (root.parent && !root.parent.visible && root.opened)
        root.close()
    }
  }

  readonly property real _availableWidth: root.parent ? root.parent.width : 0
  readonly property real _availableHeight: root.parent ? root.parent.height : 0
  readonly property real _cardMaxWidth: Math.max(0, Math.min(Style.space(340), _availableWidth - Style.space(20)))
  readonly property real _cardMaxHeight: Math.max(Style.space(80), Math.min(_availableHeight - Style.space(20), Style.space(520)))

  Rectangle {
    id: scrim
    objectName: "ConfirmDialogScrim"
    anchors.fill: parent
    color: Theme.curtain

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: function (mouse) { mouse.accepted = true }
    }
  }

  Rectangle {
    id: card
    objectName: "ConfirmDialogCard"
    width: root._cardMaxWidth
    height: Math.max(Style.space(80),
      Math.min(root._cardMaxHeight,
        Math.max(Style.space(80), contentColumn.implicitHeight + buttonFlow.implicitHeight + Style.space(10) + Style.space(20) * 2)))
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: root.danger ? Theme.danger : Theme.borderStrong
    border.width: Style.strokeWidth
    anchors.centerIn: parent

    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        root.cancelled()
        root.close()
        event.accepted = true
      } else if (event.key === Qt.Key_Tab) {
        if (confirmButton.activeFocus) cancelButton.forceActiveFocus()
        else confirmButton.forceActiveFocus()
        event.accepted = true
      } else if (event.key === Qt.Key_Backtab) {
        if (cancelButton.activeFocus) confirmButton.forceActiveFocus()
        else cancelButton.forceActiveFocus()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        if (cancelButton.activeFocus) {
          cancelButton.clicked()
        } else if (confirmButton.activeFocus) {
          confirmButton.clicked()
        } else {
          if (root.danger) cancelButton.clicked()
          else confirmButton.clicked()
        }
        event.accepted = true
      }
    }

    // The card's own background has no controls, but a click on it must not
    // reach the row underneath. The buttons are declared after this area, so
    // they stay on top and keep their own clicks.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: function (mouse) { mouse.accepted = true }
    }

    Item {
      id: contentArea
      objectName: "ConfirmDialogContentArea"
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: buttonFlow.top
      anchors.topMargin: Style.space(20)
      anchors.leftMargin: Style.space(20)
      anchors.rightMargin: Style.space(20)
      anchors.bottomMargin: Style.space(8)

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {}

        Column {
          id: contentColumn
          objectName: "ConfirmDialogContentColumn"
          width: flick.width
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
            visible: root.errorText !== ""
            text: root.errorText
            color: Theme.danger
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
        }
      }
    }

    Flow {
      id: buttonFlow
      objectName: "ConfirmDialogButtonFlow"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(20)
      anchors.rightMargin: Style.space(20)
      anchors.bottomMargin: Style.space(20)
      spacing: Style.space(8)

      readonly property bool stackButtons: cancelButton.implicitWidth + confirmButton.implicitWidth + Style.space(8)
        > (buttonFlow.width)

      ConfirmButton {
        id: cancelButton
        objectName: "ConfirmDialogCancelButton"
        width: buttonFlow.stackButtons ? buttonFlow.width : implicitWidth
        label: root.cancelText
        danger: false
        enabled: true
        onClicked: {
          root.cancelled()
          root.close()
        }
      }

      ConfirmButton {
        id: confirmButton
        objectName: "ConfirmDialogConfirmButton"
        width: buttonFlow.stackButtons ? buttonFlow.width : implicitWidth
        label: root.confirmText
        danger: root.danger
        enabled: !root.busy
        onClicked: {
          if (root.busy) return
          root.confirmed()
          if (!root.busy) root.close()
        }
      }
    }
  }

  component ConfirmButton: Item {
    id: button
    objectName: "ConfirmDialogConfirmButtonInner"

    property string label: ""
    property bool danger: false
    signal clicked()

    implicitWidth: labelText.implicitWidth + Style.space(24)
    implicitHeight: Style.space(28)

    opacity: enabled ? 1 : Style.disabledOpacity
    activeFocusOnTab: false

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: mouse.pressed && button.enabled
        ? Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, Style.control.pressedFillAlpha)
        : (mouse.containsMouse && button.enabled
          ? Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, Style.control.hoverFillAlpha)
          : "transparent")
      border.color: button.activeFocus ? Theme.primary : "transparent"
      border.width: button.activeFocus ? Style.strokeWidth : 0
      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

    }

    readonly property color foreground: button.danger ? Theme.danger : Theme.fg

    Text {
      id: labelText
      anchors.centerIn: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)
      width: Math.max(0, Math.min(implicitWidth, parent.width - Style.space(8)))
      text: button.label
      color: button.danger ? Theme.danger : Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: button.enabled
      hoverEnabled: true
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (!button.enabled) return
        button.forceActiveFocus()
        button.clicked()
      }
    }
  }
}
