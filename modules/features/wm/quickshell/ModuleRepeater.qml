import QtQuick
import "."
import "Ui"

// Loads the modules for one bar.json section. Shared by the row and the column a
// Section draws, so a module is built identically whichever way the bar runs.
//
// Declared as an id rather than built inline: `Component { ... }` is an object
// declaration, so it cannot be passed as a call argument.
Repeater {
  id: repeater

  property var modules: []

  // The bar.json section these modules came from, which is what decides the edge
  // a module keeps fixed when it grows. Set by Section.
  property string sectionName: ""
  property string screenName: ""

  model: repeater.modules

  // Which edge of a module stays put when it grows, so a widening one does not
  // shove its neighbours: "start" is the leading edge (left, or top on a vertical
  // bar), "end" the trailing one, and "center" means it grows both ways.
  //
  // It follows from how each section is anchored in shell.qml. A section pinned
  // to one edge of the bar grows away from that edge, so every module in it keeps
  // the near edge; the centre box is a different case, because it is centred as
  // one group and so has to grow outwards from the middle — its first module
  // leftward and its last rightward, or the group would drift off centre.
  function fixedEdgeFor(position, total) {
    const name = repeater.sectionName

    if (name === "center") {
      if (total <= 1) return "center"
      if (position === 0) return "end"
      if (position === total - 1) return "start"
      return "center"
    }

    if (name === "left" || name === "centerEnd") return "start"
    if (name === "right" || name === "centerBegin") return "end"

    return "center"
  }

  function moduleVisible(entry, screenName) {
    if (!entry) return true
    const screens = entry.screens
    if (screens === undefined || screens === null) return true
    if (typeof screens === "string") {
      if (screens === "" || screens === "all") return true
      return screens === screenName
    }
    if (!Array.isArray(screens) || screens.length === 0) return true
    if (screens.indexOf("all") !== -1) return true
    if (screenName === "") return true
    return screens.indexOf(screenName) !== -1
  }

  // Resolve a `type: "qml"` entry to a file URL. An explicit `source` wins and
  // may be absolute or relative to the quickshell config directory; otherwise
  // the module is expected at modules/<id>.qml, the same convention Omarchy uses
  // for its drop-in bar modules.
  function qmlSource(entry) {
    if (entry.source) {
      const s = String(entry.source)
      return s.charAt(0) === "/" ? "file://" + s : s
    }

    return "modules/" + String(entry.id) + ".qml"
  }

  delegate: Loader {
    id: loader
    required property var modelData
    required property int index

    // Follow the pointer while this module is being rearranged. The layout does
    // not move during the drag, so the module only dims and a line shows the gap
    // the release would fill.
    opacity: BarDrag.active && BarDrag.sourceSection === repeater.sectionName && BarDrag.sourceIndex === loader.index
      ? 0.35
      : 1

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(120) }
    }

    function dragPoint() {
      const host = BarDrag.rootFor(loader)
      if (!host) return null
      const point = dragHandler.centroid.position
      return loader.mapToItem(host, point.x, point.y)
    }

    // A module that hides itself takes its slot with it. A Loader measures the
    // width of what it loaded whether or not that thing is drawn, and the bar
    // lays out the Loaders — so a widget that sets `visible: false` (the tray
    // with nothing in it, the sudo key on a machine that asks for a password, an
    // indicator that is off, the weather before its first reading) used to leave
    // a gap exactly the size of itself on the bar.
    visible: item ? item.wantsSlot && repeater.moduleVisible(modelData, repeater.screenName) : false

    Component {
      id: commandFactory
      CommandModule { entry: loader.modelData }
    }

    Component.onCompleted: {
      const entry = modelData
      if (!entry) return

      if (entry.type === "command") {
        loader.sourceComponent = commandFactory
      } else if (entry.type === "qml") {
        // `source` and `sourceComponent` are mutually exclusive on a Loader, so
        // only one of the two is ever set for a given delegate.
        loader.source = repeater.qmlSource(entry)
      } else {
        const component = ModuleRegistry.registry[entry.id]
        if (component) {
          loader.sourceComponent = component
          return
        }

        // Not a built-in: the manifest may name a file for it. That is the whole
        // plugin path — a widget is a source and a section, not a registry edit.
        const plugin = BarConfig.plugin(entry.id)
        if (plugin && plugin.source) {
          loader.source = plugin.source
          return
        }

        console.warn("quickshell bar: unknown module id " + entry.id)
      }
    }

    // Loaded from the registry with its defaults, then handed its layout entry.
    // Every module declares `entry`, so this is how per-module settings such as
    // a clock format reach it. `fixedEdge` is set the same way, and every widget
    // should bind to it rather than read it once, since moving a widget to
    // another section changes it in place.
    //
    // A `type: "qml"` module additionally receives `bar` (the handle above),
    // `moduleName` and `settings`, matching the contract Omarchy documents for
    // its drop-in modules.
    onLoaded: {
      if (!loader.item) return

      if (loader.item.entry !== undefined) loader.item.entry = modelData
      if (loader.item.fixedEdge !== undefined) {
        loader.item.fixedEdge = repeater.fixedEdgeFor(index, repeater.modules.length)
      }

      if (modelData && modelData.type === "qml") {
        if (loader.item.bar !== undefined) loader.item.bar = Bar
        if (loader.item.moduleName !== undefined) loader.item.moduleName = modelData.id
        if (loader.item.settings !== undefined) loader.item.settings = modelData
      }
    }

    onStatusChanged: {
      if (loader.status === Loader.Error) {
        console.warn("quickshell bar: failed to load qml module "
          + (modelData ? modelData.id : "?") + " from " + loader.source)
      }
    }

    // Drag to rearrange. The handler does not move the Loader — the section's
    // row or column owns its position — it only reports the gesture. The
    // threshold is what keeps a click a click: a small wobble inside a button
    // must not turn into a reorder.
    DragHandler {
      id: dragHandler

      target: null
      acceptedButtons: Qt.LeftButton
      dragThreshold: Style.space(8)
      cursorShape: Qt.ClosedHandCursor
      enabled: loader.visible && loader.item !== null && modelData && modelData.id !== undefined
      grabPermissions: PointerHandler.CanTakeOverFromItems
        | PointerHandler.CanTakeOverFromHandlersOfDifferentType

      onActiveChanged: {
        if (dragHandler.active) {
          const point = loader.dragPoint()
          if (point) {
            BarDrag.begin(repeater.sectionName, loader.index, String(modelData.id),
              point.x, point.y, BarDrag.rootFor(loader))
          }
        } else {
          BarDrag.finish()
        }
      }

      onTranslationChanged: {
        if (!dragHandler.active) return
        const point = loader.dragPoint()
        if (point) BarDrag.update(point.x, point.y)
      }

      onCanceled: BarDrag.cancel()
    }
  }
}