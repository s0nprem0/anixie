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
    Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.base) } }
  }

  // Transparent, and the whole control's opacity follows the thumb's rather than
  // the thumb's following its own. The trough used to paint Theme.bg at full
  // strength while the thumb faded out, so a scrollbar with nothing to scroll
  // still laid a strip of background down the side of whatever it sat on. That
  // was invisible in the dock, where the trough matched the dock, and obvious on
  // the picker, where the trough sat on the card's surface instead.
  opacity: policy === ScrollBar.AlwaysOn || active ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Style.duration(Style.motion.base) } }

  background: Item {}
}