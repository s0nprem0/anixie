import QtQuick
import ".."
import "../Ui"

// What the power key should open: lock, sleep, or leave — with the three that
// lose something asking first.
//
// Log out asks the compositor to exit, not logind to terminate the session.
// `loginctl terminate-session` kills Hyprland with SIGTERM instead of letting it
// shut down, which makes the display manager's session helper crash and leaves
// the machine on a black screen with no greeter. `hyprctl dispatch exit` is the
// clean path back to the greeter. The logind call stays behind it as a fallback for a
// compositor that is stuck and cannot answer hyprctl.
Item {
  id: root

  // A panel only exists while it is open, so a confirmation cannot outlive it.
  property string pending: ""

  function run(command) {
    if (command === "") return
    Commands.run(command)
    PanelHost.closeFocused()
  }

  function ask(command, question, detail) {
    root.pending = command
    confirm.text = question
    confirm.detail = detail
    confirm.open()
  }

  implicitWidth: Style.space(320)
  implicitHeight: card.implicitHeight

  Panel {
    id: card
    anchors.fill: parent

    PanelHero {
      width: card.contentWidth
      glyph: Util.bolt
      title: "Session"
      subtitle: "lock, sleep, or leave"
    }

    PanelSeparator {}

    PanelActionButton {
      width: card.contentWidth
      label: "Lock"
      value: "Super+Ctrl+L"
      navigational: false
      onClicked: {
        LockHost.lock()
        PanelHost.closeFocused()
      }
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Suspend"
      navigational: false
      onClicked: {
        LockHost.lockAndSuspend()
        PanelHost.closeFocused()
      }
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Log out"
      navigational: false
      onClicked: root.ask(
        "hyprctl dispatch 'hl.dsp.exit()' || loginctl terminate-session \"$XDG_SESSION_ID\"",
        "Log out of this session?",
        "Everything open will be closed.")
    }

    PanelSeparator {}

    PanelActionButton {
      width: card.contentWidth
      label: "Restart"
      danger: true
      navigational: false
      onClicked: root.ask("systemctl reboot", "Restart the machine?", "")
    }

    PanelActionButton {
      width: card.contentWidth
      label: "Shut down"
      danger: true
      navigational: false
      onClicked: root.ask("systemctl poweroff", "Shut the machine down?", "")
    }
  }

  // Outside the card, not inside it: a Panel's children go into its content
  // column, and a dialog laid out as a row would be zero-sized.
  ConfirmDialog {
    id: confirm
    anchors.fill: parent
    confirmText: "Yes"
    danger: true
    onConfirmed: root.run(root.pending)
    onCancelled: root.pending = ""
  }
}
