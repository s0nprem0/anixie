import QtQuick
import ".."
import "../Ui"

// The dock: every open window, grouped one tile per application, so a window can
// be brought back by clicking it.
//
// It reserves a strip of the screen while it is up, the same way the bar does,
// so windows are laid out below it instead of running underneath it — a dock that
// windows slid under would be worse than useless.
Item {
  id: root

  readonly property var apps: DockHost.apps
  readonly property bool empty: root.apps.length === 0

  // Fills whatever the dock window gives it. Its own implicit size is only a
  // fallback: the window states the strip's width so that width and the space
  // Hyprland reserves cannot disagree with each other.
  implicitWidth: Style.space(360)
  implicitHeight: Style.bar.sizeHorizontal

  Rectangle {
    anchors.fill: parent
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth
  }

  // Everything is in one scrollable column: a session can have more windows than
  // a screen has room for, and the ones that fall off the bottom are the least
  // interesting rather than the most.
  ListView {
    id: list

    anchors.fill: parent
    anchors.margins: Style.space(6)
    clip: true
    spacing: Style.space(4)
    model: root.apps
    orientation: ListView.Vertical

    delegate: DockTile {
      required property var modelData

      width: ListView.view.width
      app: modelData
    }

    ScrollBar.vertical: ScrollBar {
      // Only offered when there is something to scroll to; a strip on every dock
      // that fits its contents would be furniture, not information.
      visible: list.contentHeight > list.height
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.empty
    text: "No windows open"
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}