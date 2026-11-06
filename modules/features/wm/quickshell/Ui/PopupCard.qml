pragma ComponentBehavior: Bound
import QtQuick
import ".."

// A small anchored card surface: the container a PopupMenuRow (or any content)
// sits in. Use for popups, dropdowns, and transient menus so the surface
// treatment stays consistent with the rest of the shell.
Rectangle {
  id: root

  property int padding: Style.space(4)
  property color surfaceColor: Theme.surface
  property color borderColor: Theme.border
  property int cornerRadius: Theme.cornerRadius

  color: root.surfaceColor
  border.width: Style.strokeWidth
  border.color: root.borderColor
  radius: root.cornerRadius
  clip: true
}
