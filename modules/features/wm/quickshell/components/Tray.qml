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

  // A hover reveal is passive: it opens the drawer without taking the keyboard,
  // and closes it again when the pointer leaves both the tray and the drawer.
  // A drawer opened by clicking the handle is left alone until it is dismissed.
  property bool drawerHovered: false
  property bool hoverOpened: false

  wantsSlot: root.items.length > 0 || root.parked.length > 0
  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  // The drawer opens from the handle below, and from the command line by name.
  Component.onCompleted: BarContext.trayItem = root

  function openDrawer() {
    if (root.parked.length === 0 || PanelHost.isOpen("tray")) return

    root.hoverOpened = true
    PanelHost.showPassive("tray", parkedButton, root.drawer)
  }

  function closeDrawer() {
    if (!PanelHost.isOpen("tray")) {
      root.hoverOpened = false
      root.drawerHovered = false
      return
    }

    if (!root.hoverOpened) return
    if (root.drawerHovered || trayHover.hovered) return
    // A parked widget may have opened its own panel from the drawer. Closing the
    // drawer would take that panel's anchor away with it, so it stays until the
    // panel opened from it is gone.
    if (PanelHost.openPanels.count > 1) return

    PanelHost.close("tray")
    root.hoverOpened = false
  }

  function openMenu(button) {
    if (!button.item || !button.item.hasMenu) return

    // The anchor resolves against the icon itself, so the menu lands under the
    // icon that was clicked rather than at a fixed spot.
    menuAnchor.anchor.item = button
    menuAnchor.menu = button.item.menu
    menuAnchor.open()
  }

  // Hovering the tray reveals the drawer. The delay keeps a pointer merely
  // crossing the bar from opening it; leaving waits a little longer so the
  // pointer can cross the gap into the drawer.
  HoverHandler {
    id: trayHover

    onHoveredChanged: {
      if (hovered) {
        root.hoverClose.stop()
        if (!PanelHost.isOpen("tray")) root.hoverOpen.restart()
      } else {
        root.hoverOpen.stop()
        if (root.hoverOpened) root.hoverClose.restart()
      }
    }
  }

  Timer {
    id: hoverOpen
    interval: 250
    onTriggered: root.openDrawer()
  }

  Timer {
    id: hoverClose
    interval: 300
    onTriggered: root.closeDrawer()
  }

  onParkedChanged: {
    if (root.parked.length === 0) {
      if (hoverOpen) hoverOpen.stop()
      if (hoverClose) hoverClose.stop()
      root.hoverOpened = false
      root.drawerHovered = false
      if (PanelHost.isOpen("tray")) PanelHost.close("tray")
    } else if (trayHover && trayHover.hovered && !PanelHost.isOpen("tray")) {
      if (hoverOpen) hoverOpen.restart()
    }
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
        root.hoverOpen.stop()
        root.hoverClose.stop()
        root.hoverOpened = false
        PanelHost.toggle("tray", parkedButton, root.drawer)
      }
    }
  }

  // The drawer. A panel rather than a floating strip of its own: it dismisses on
  // a click outside, takes the keyboard when opened by a click, and a widget
  // opened from it can have its own panel beside it, which a strip that has to
  // stay inside the bar's height could not.
  Component {
    id: drawerComponent

    Panel {
      id: trayCard

      // Crossing the gap from the bar into the drawer must not close it. The
      // close timer is cancelled while the pointer is on the card, and restarted
      // when it leaves.
      onPointerInsideChanged: {
        root.drawerHovered = trayCard.pointerInside
        if (trayCard.pointerInside) root.hoverClose.stop()
        else if (root.hoverOpened) root.hoverClose.restart()
      }

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
