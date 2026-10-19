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

  // Widgets put away in the tray. They are bar modules, not tray icons: the tray
  // is where a widget goes when it is wanted but not always in view, and the
  // drawer is where it comes back out.
  readonly property var parked: BarConfig.section("tray")

  readonly property Component drawer: drawerComponent

  wantsSlot: root.items.length > 0 || root.parked.length > 0
  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  // The drawer opens from the handle below, and from the command line by name.
  Component.onCompleted: BarContext.trayItem = root

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

    // The handle. Only when there is something parked — an empty tray does not
    // need to say it is empty.
    BarIconButton {
      id: parkedButton
      visible: root.parked.length > 0
      text: Util.chevronDown
      labelText: ""
      tooltipText: root.parked.length
        + (root.parked.length === 1 ? " widget parked" : " widgets parked")
        + " · click to open"
      onPressed: function () {
        PanelHost.toggle("tray", parkedButton, root.drawer)
      }
    }
  }

  // The drawer. A panel rather than a floating strip of its own: it dismisses on
  // a click outside, takes the keyboard, and a widget opened from it can have its
  // own panel beside it, which a strip that has to stay inside the bar's height
  // could not.
  Component {
    id: drawerComponent

    Panel {
      id: trayCard

      PanelHero {
        width: trayCard.contentWidth
        glyph: Util.menu
        title: "Parked"
        subtitle: root.parked.length
          + (root.parked.length === 1 ? " widget" : " widgets")
      }

      PanelSeparator {}

      Repeater {
        model: root.parked

        delegate: Loader {
          id: parkedLoader
          required property var modelData

          width: trayCard.contentWidth
          height: item ? item.implicitHeight : 0
          sourceComponent: ModuleRegistry.registry[modelData.id] || null

          onLoaded: {
            if (!item) return
            if (item.entry !== undefined) item.entry = modelData
            if (item.fixedEdge !== undefined) item.fixedEdge = "center"
          }
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
