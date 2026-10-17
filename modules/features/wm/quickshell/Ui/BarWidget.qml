import QtQuick
import ".."

// Base item every bar module extends. `entry` is the module's own object from
// bar.json, handed over by Section once the module has loaded.
Item {
  id: root

  property string moduleName: ""
  property var entry: ({})

  // The edge that stays put when this module grows, so a widening label does
  // not shove its neighbours sideways: "start", "end", or "center" when it
  // grows both ways.
  property string fixedEdge: "center"

  readonly property bool vertical: BarContext.vertical
  readonly property int barSize: Style.bar.sizeHorizontal

  // Read one value out of this module's bar.json entry, with a fallback.
  function setting(name, fallback) {
    const value = root.entry ? root.entry[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}