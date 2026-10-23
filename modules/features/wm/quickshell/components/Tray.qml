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

  // The drawer opens by clicking the handle or with `bar tray`, never on hover.
  // A hover reveal made crossing the right end of the bar enough to open it,
  // and a tray icon appearing could shift the layout under a resting pointer
  // and open the drawer with no click at all.
  wantsSlot: root.items.length > 0 || root.parked.length > 0
  implicitWidth: row.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  // The drawer opens from the handle below, and from the command line by name.
  Component.onCompleted: BarContext.registerTray(root)
  Component.onDestruction: BarContext.unregisterTray(root)

  readonly property string screenName: Screens.nameOf(root)
  readonly property bool drawerOpen: PanelHost.isOpen("tray", root.screenName)

  // The path for an item's icon, trying every name it might have gone by.
  //
  // A StatusNotifierItem is not required to publish a theme icon. Electron and
  // flatpak apps often leave IconName empty because their icon arrives as a
  // pixmap, which this service does not expose, and some publish an icon name
  // that exists only in their desktop entry. Falling back to
  // application-x-executable for all of those is why every one of them looked
  // the same. The order is: what the item says, what its desktop entry says,
  // the app id or title as a theme name, and the generic icon last.
  function iconPath(item) {
    if (!item) return ""

    function resolve(name) {
      if (!name) return ""

      const value = String(name)

      // The tray service publishes a theme icon as an image:// URL. Strip that
      // back to the name so the existence check runs on what the provider is
      // looking for; otherwise a missing icon becomes Quickshell's black and
      // purple missing-image square instead of falling through to the next
      // candidate in the list.
      if (value.indexOf("image://icon/") === 0) {
        const rest = value.slice("image://icon/".length)
        const query = rest.indexOf("?")
        const iconName = query === -1 ? rest : rest.slice(0, query)
        return Quickshell.iconPath(iconName, true)
      }

      // Any other image provider URL is already a usable source.
      if (value.indexOf("image://") === 0) return value

      // A few items publish a path instead of a theme name. iconPath only
      // understands theme names, so hand the file to Image as a URL.
      if (value.indexOf("file://") === 0) return value
      if (value.charAt(0) === "/") return "file://" + value

      return Quickshell.iconPath(value, true)
    }

    // What the item itself published.
    const direct = resolve(item.icon)
    if (direct !== "") return direct

    const id = String(item.id || "")
    const title = String(item.title || "")

    // Some items name the desktop file, some the app id without the suffix,
    // and flatpak ids are reverse-DNS. byId is exact, heuristicLookup is what
    // covers a title that is the display name rather than the file id.
    const entry = (id !== "" ? DesktopEntries.byId(id) : null)
      || (id !== "" ? DesktopEntries.byId(id + ".desktop") : null)
      || (title !== "" ? DesktopEntries.heuristicLookup(title) : null)

    const fromEntry = resolve(entry ? entry.icon : "")
    if (fromEntry !== "") return fromEntry

    // Last resort before the generic icon: the app id is often the icon name
    // even when no desktop file on this machine agrees.
    const names = []
    function add(name) {
      if (name && names.indexOf(name) === -1) names.push(String(name))
    }
    if (id !== "") {
      add(id)
      add(id.replace(/\.desktop$/, ""))
      add(id.toLowerCase())
    }

    for (let i = 0; i < names.length; i++) {
      const path = resolve(names[i])
      if (path !== "") return path
    }

    return Quickshell.iconPath("application-x-executable", true)
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

  // A drawer whose widgets all stopped reporting — Dropbox not installed, the
  // keyboard layout collapsed to one entry — has nothing left to show. Close
  // it rather than leaving an empty panel floating.
  onParkedChanged: {
    if (root.parked.length === 0 && root.drawerOpen) PanelHost.close("tray", root.screenName)
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
          source: root.iconPath(button.item)
          sourceSize.width: Style.bar.iconSize * 2
          sourceSize.height: Style.bar.iconSize * 2
          width: Style.bar.iconSize
          height: Style.bar.iconSize
          fillMode: Image.PreserveAspectFit
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
  // a click outside, takes the keyboard when opened by a click, and a widget
  // opened from it can have its own panel beside it, which a strip that has to
  // stay inside the bar's height could not.
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
