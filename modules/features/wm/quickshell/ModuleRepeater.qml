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
  model: repeater.modules

  delegate: Loader {
    id: loader
    required property var modelData

    Component {
      id: commandFactory
      CommandModule { entry: loader.modelData }
    }

    Component.onCompleted: {
      const entry = modelData
      if (!entry) return

      if (entry.type === "command") {
        loader.sourceComponent = commandFactory
      } else {
        const component = ModuleRegistry.registry[entry.id]
        if (component) loader.sourceComponent = component
        else console.warn("quickshell bar: unknown module id " + entry.id)
      }
    }

    // Loaded from the registry with its defaults, then handed its layout entry.
    // Every module declares `entry`, so this is how per-module settings such as
    // a clock format reach it.
    onLoaded: {
      if (loader.item && loader.item.entry !== undefined) loader.item.entry = modelData
    }
  }
}