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

  // Whether this module wants a slot on the bar.
  //
  // Separate from `visible` because visibility is contagious: hiding a parent
  // makes a child's `visible` read false, and the bar's Loader has to read a
  // module's wish without being the thing that decides it. A module that hides
  // itself sets this; the Loader follows it, and the slot goes with it.
  //
  // Not called `shown`: the indicators already use that name for the list of
  // indicators that are on.
  property bool wantsSlot: true

  visible: root.wantsSlot

  readonly property bool vertical: BarContext.vertical
  readonly property int barSize: Style.bar.sizeHorizontal

  // Panels this module owns. Each bar is a separate instance on a separate
  // output, so each copy registers under the same name. Keeping the list here
  // means the copy goes when its bar does — on a hotplug or an edge change the
  // old widgets are destroyed, and a registration left behind would point at a
  // dead anchor.
  property var registeredPanels: []

  function registerPanel(name, anchor, builder) {
    if (!name || !anchor || !builder) return

    root.registeredPanels = root.registeredPanels.concat([{ name: name, anchor: anchor }])
    PanelRegistry.register(name, anchor, builder)
  }

  Component.onDestruction: {
    for (let i = 0; i < root.registeredPanels.length; i++) {
      const panel = root.registeredPanels[i]
      PanelRegistry.unregister(panel.name, panel.anchor)
    }
  }

  // Read one value out of this module's bar.json entry, with a fallback.
  function setting(name, fallback) {
    const value = root.entry ? root.entry[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}