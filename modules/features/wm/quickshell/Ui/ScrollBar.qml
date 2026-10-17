import QtQuick
import QtQuick.Controls.Basic
import ".."

// A themed scrollbar for panel content that outgrows the panel.
ScrollBar {
  id: control

  implicitWidth: Style.space(6)

  contentItem: Rectangle {
    implicitWidth: control.width
    radius: width / 2
    color: control.pressed ? Theme.primary : Theme.muted
    opacity: control.policy === ScrollBar.AlwaysOn || control.active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(150) } }
  }

  background: Rectangle {
    implicitWidth: control.width
    radius: width / 2
    color: Theme.bg
  }
}