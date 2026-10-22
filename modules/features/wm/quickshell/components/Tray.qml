import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import ".."
import "../Ui"

// System tray: whatever has registered itself over StatusNotifierItem, left to
// right, in the order the service reports them.
//
// Menus come from the item itself: `display()` hands the application's DBusMenu
// to Quickshell's platform-menu path, so the whole submenu tree, checkmarks and
// separators come for free and a menu that is built lazily is waited for. An
// item with no menu gets the shell's own two-entry menu instead of a dead right
// button.
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
  Component.onCompleted: BarContext.registerTray(root)
  Component.onDestruction: BarContext.unregisterTray(root)

  readonly property string screenName: Screens.nameOf(root)
  readonly property bool drawerOpen: PanelHost.isOpen("tray", root.screenName)

  function openDrawer() {
    if (root.parked.length === 0 || root.drawerOpen) return

    root.hoverOpened = true
    PanelHost.showPassive("tray", parkedButton, root.drawer)
  }

  function closeDrawer() {
    if (!root.drawerOpen) {
      root.hoverOpened = false
      root.drawerHovered = false
      return
    }

    if (!root.hoverOpened) return
    if (root.drawerHovered || trayHover.hovered) return
    // A parked widget may have opened its own panel from the drawer. Closing the
    // drawer would take that panel's anchor away with it, so it stays until the
    // panel opened from it is gone.
    if (PanelHost.countFor(root.screenName) > 1) return

    PanelHost.close("tray", root.screenName)
    root.hoverOpened = false
  }

  function openMenu(button) {
    const item = button.item
    if (!item) return

    const window = button.QsWindow ? button.QsWindow.window : null
    if (item.hasMenu && window && typeof item.display === "function") {
      // `display()` is the tray item's own platform-menu entry point. Unlike
      // attaching the handle to a QsMenuAnchor, it waits for the DBusMenu
      // layout to arrive before showing anything, which is what a menu built
      // lazily — Discord and most Electron apps — needs.
      const point = button.QsWindow ? button.QsWindow.itemPosition(button) : Qt.point(0, 0)
      item.display(window, Math.round(point.x), Math.round(point.y + button.height))
      return
    }

    // No application menu. Give the right button something useful rather than
    // leaving it dead: the two activations the item itself offers.
    ContextMenuHost.open([
      { label: "Activate", enabled: !item.onlyMenu, action: function () { item.activate() } },
      { label: "Secondary activate", action: function () { item.secondaryActivate() } }
    ], button)
  }

  // Hovering the tray reveals the drawer. The delay keeps a pointer merely
  // crossing the bar from opening it; leaving waits a little longer so the
  // pointer can cross the gap into the drawer.
  HoverHandler {
    id: trayHover

    onHoveredChanged: {
      if (hovered) {
        hoverClose.stop()
        if (!root.drawerOpen) hoverOpen.restart()
      } else {
        hoverOpen.stop()
        if (root.hoverOpened) hoverClose.restart()
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
      if (root.drawerOpen) PanelHost.close("tray", root.screenName)
    } else if (trayHover && trayHover.hovered && !root.drawerOpen) {
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
          } else if (which === Qt.MiddleButton) {
            button.item.secondaryActivate()
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
        hoverOpen.stop()
        hoverClose.stop()
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
        if (trayCard.pointerInside) hoverClose.stop()
        else if (root.hoverOpened) hoverClose.restart()
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
          // A parked widget can still decide it has nothing to say — Dropbox
          // when it is not installed, the keyboard layout when there is only
          // one. Keep its slot out of the drawer entirely, not just invisible,
          // or the hidden widget leaves a gap the size of its bar slot.
          visible: item ? item.wantsSlot : false
          height: item && item.wantsSlot ? item.implicitHeight : 0
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
}
