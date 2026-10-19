pragma Singleton

import QtQuick
import "Ui"

// Orientation, read by the bar itself and by every module.
//
// Widgets need to know whether they are on a horizontal or a vertical bar: a
// label that fits beside an icon on a top bar has nowhere to go on a side bar,
// where the bar is only as wide as an icon. Passing this down through a
// singleton keeps it out of every module's constructor.
//
// The value comes from Theme, which Nix renders, rather than from bar.json,
// because the bar window is built once and cannot be re-anchored afterwards.
QtObject {
  id: root

  property string position: Theme.position

  readonly property bool vertical: position === "left" || position === "right"

  // Whether the bar is on screen. Hidden keeps the window itself — and the item
  // every panel anchors to — alive, so a panel opened from a hotkey still has
  // somewhere to attach, and the reserved strip is given back to the workspace.
  // Unmapping the window instead would take the anchors with it and leave the
  // panel with nothing to open against.
  property bool shown: true

  function toggle() {
    shown = !shown
  }

  // How far a module may run before it stops being worth showing.
  readonly property int maxBarSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // The bar's sections, in the order they are declared, each as { name, item }.
  // A drag needs to know what it is hovering over, and the sections are the only
  // things that know where they are on screen.
  property var sections: []

  function registerSection(name, item) {
    const next = []
    for (let i = 0; i < root.sections.length; i++) {
      if (root.sections[i].item !== item) next.push(root.sections[i])
    }
    next.push({ name: name, item: item })
    root.sections = next
  }

  // Which section, and where in it, a scene point lands. Empty when the pointer
  // is not over the bar at all — a drag that ends off the bar should do nothing
  // rather than throw the widget at the nearest section.
  function dropTarget(x, y) {
    for (let i = 0; i < root.sections.length; i++) {
      const section = root.sections[i]
      const item = section.item
      if (!item || item.visible === false) continue

      const origin = item.mapToItem(null, 0, 0)
      if (x < origin.x || x > origin.x + item.width) continue
      if (y < origin.y || y > origin.y + item.height) continue

      return { section: section.name, index: item.indexFor(x) }
    }
    return null
  }
}