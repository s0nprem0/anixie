import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import ".."
import "../Ui"

// System tray: whatever has registered itself over StatusNotifierItem, left to
// right, in the order the service reports them.
//
// Menus are handed to a QsMenuAnchor rather than drawn here. That is Quickshell's
// display anchor for platform menus — the item supplies its menu, the anchor owns
// the popup and its placement — so the whole submenu tree, checkmarks and
// separators come for free.
BarWidget {
  id: root

  readonly property var items: SystemTray.items ? SystemTray.items.values : []

  visible: root.items.length > 0
  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  function openMenu(button) {
    if (!button.item || !button.item.hasMenu) return

    // The anchor resolves against the icon itself, so the menu lands under the
    // icon that was clicked rather than at a fixed spot.
    menuAnchor.anchor.item = button
    menuAnchor.menu = button.item.menu
    menuAnchor.open()
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      model: root.items

      delegate: WidgetButton {
        id: button
        required property var modelData

        readonly property var item: modelData

        // A tray icon is an image from the icon theme, not text or a glyph, so
        // the usual content check is overridden and the image below stands in
        // for it. The slot keeps every icon the same size regardless.
        hasVisualContent: true
        fixedWidth: Style.bar.iconSlot
        fixedHeight: Style.bar.iconSlot
        active: false
        tooltipText: {
          const title = button.item.tooltipTitle || button.item.title || ""
          const description = button.item.tooltipDescription || ""
          return description !== "" ? title + "\n" + description : title
        }

        onPressed: function (which) {
          if (which === Qt.RightButton) {
            root.openMenu(button)
          } else if (which === Qt.LeftButton) {
            // An item that is only a menu has no activate action of its own, so
            // a left click that would otherwise do nothing opens it instead.
            if (button.item.onlyMenu && button.item.hasMenu) root.openMenu(button)
            else button.item.activate()
          }
        }

        onWheelMoved: function (delta) {
          button.item.scroll(delta > 0 ? 1 : -1, false)
        }

        Image {
          anchors.centerIn: parent
          source: button.item.icon !== ""
            ? Quickshell.iconPath(button.item.icon, "application-x-executable")
            : ""
          sourceSize.width: Style.bar.iconSize * 2
          sourceSize.height: Style.bar.iconSize * 2
          width: Style.bar.iconSize
          height: Style.bar.iconSize
          smooth: true
        }
      }
    }
  }

  QsMenuAnchor {
    id: menuAnchor

    // Below the icon rather than over it, so the bar itself stays clear.
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
  }
}
