import QtQuick
import QtQuick.Controls.Basic
import ".."

// A themed scrollbar for panel content that outgrows the panel.
ScrollBar {
  id: control

  implicitWidth: control.orientation === Qt.Vertical ? Style.space(6) : 0
  implicitHeight: control.orientation === Qt.Horizontal ? Style.space(6) : 0

  contentItem: Rectangle {
    radius: Math.min(width, height) / 2
    color: control.pressed ? Theme.primary : Theme.muted
  }

  // AlwaysOn/AlwaysOff take precedence; AsNeeded follows activity
  opacity: policy === ScrollBar.AlwaysOff
    ? 0
    : (policy === ScrollBar.AlwaysOn ? 1 : (control.active ? 1 : 0))
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.base) } }

  background: Item {}
}