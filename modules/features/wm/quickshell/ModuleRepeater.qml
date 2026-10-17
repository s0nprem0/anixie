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
        if (component) loader.sourceComponent = component
        else console.warn("quickshell bar: unknown module id " + entry.id)
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
  }
}