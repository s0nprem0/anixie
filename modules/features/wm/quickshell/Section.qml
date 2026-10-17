import QtQuick
import "."

// One horizontal run of bar modules, as named by a bar.json section.
Row {
  id: root
  spacing: Theme.gap

  property var entries: []

  Repeater {
    model: root.entries

    delegate: Loader {
      id: loader
      required property var modelData

      // Declared here rather than built inline: `Component { ... }` is an object
      // declaration, so it cannot be passed straight to the loader.
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

      // Loaded from the registry with its defaults, then handed its layout
      // entry. Every module declares `entry`, so this is how per-module
      // settings such as a clock format reach it.
      onLoaded: {
        if (loader.item && loader.item.entry !== undefined) loader.item.entry = modelData
      }
    }
  }
}