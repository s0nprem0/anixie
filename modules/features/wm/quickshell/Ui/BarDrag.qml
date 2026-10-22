pragma Singleton

import QtQuick
import ".."

// Rearranging the bar with the pointer.
//
// BarConfig.move() already knows how to persist a new section and index; what
// was missing was a way to produce one from a drag. A module's DragHandler
// starts this, every move asks for the nearest gap, and the release is the one
// write. The layout is not touched while the pointer is down.
//
// Everything is measured in barRoot's coordinates. The sections register
// themselves because a gap can only be found from the items actually laid out:
// a hidden module has no width on the bar, and the centre sections grow away
// from the clock rather than from the screen edge.
QtObject {
  id: root

  // The bar the drag started on. Set from the module's own screen rather than
  // from whichever bar registered last, because every screen has one.
  property Item barRoot: null

  // Bars by screen name. shell.qml registers one per connected output, and a
  // module's coordinates are measured against the bar on its own display.
  property var roots: ({})

  function registerBar(item) {
    if (!item) return

    const name = Screens.nameOf(item)
    if (!name) return

    const next = {}
    for (const key in root.roots) next[key] = root.roots[key]
    next[name] = item
    root.roots = next
  }

  function unregisterBar(item) {
    if (!item) return

    const name = Screens.nameOf(item)
    let found = root.roots[name] === item ? name : ""
    if (!found) {
      for (const key in root.roots) {
        if (root.roots[key] === item) {
          found = key
          break
        }
      }
    }
    if (!found) return

    const next = {}
    for (const key in root.roots) if (key !== found) next[key] = root.roots[key]
    root.roots = next
  }

  function rootFor(item) {
    const name = Screens.nameOf(item)
    return root.roots[name] || root.barRoot
  }

  property bool active: false
  property string sourceId: ""
  property string sourceSection: ""
  property int sourceIndex: -1

  property string targetSection: ""
  property int targetIndex: -1
  property bool targetValid: false
  property rect indicatorRect: Qt.rect(0, 0, 0, 0)

  // The bar's visual order. The drag walks this rather than the registration
  // order, so a section rebuilt at any time still lands in the right place.
  readonly property var order: ["left", "centerBegin", "center", "centerEnd", "right"]
  property var sections: ({})

  function sectionKey(name, item) {
    return Screens.nameOf(item) + "|" + name
  }

  function sectionFor(screenName, name) {
    return root.sections[screenName + "|" + name] || null
  }

  function registerSection(name, item) {
    if (!name || !item) return

    const key = root.sectionKey(name, item)

    const next = {}
    for (const other in root.sections) next[other] = root.sections[other]
    next[key] = item
    root.sections = next
  }

  function unregisterSection(name, item) {
    if (!item) return

    const key = root.sectionKey(name, item)
    let found = root.sections[key] === item ? key : ""
    if (!found) {
      for (const other in root.sections) {
        if (root.sections[other] === item) {
          found = other
          break
        }
      }
    }
    if (!found) return

    const next = {}
    for (const other in root.sections) {
      if (other !== found) next[other] = root.sections[other]
    }
    root.sections = next
  }

  function axisStart(item) {
    const point = item.mapToItem(root.barRoot, 0, 0)
    return BarContext.vertical ? point.y : point.x
  }

  function axisEnd(item) {
    const point = item.mapToItem(root.barRoot, 0, 0)
    return BarContext.vertical ? point.y + item.height : point.x + item.width
  }

  function crossCentre(item) {
    const point = item.mapToItem(root.barRoot, 0, 0)
    return BarContext.vertical ? point.x + item.width / 2 : point.y + item.height / 2
  }

  function sectionCentre(section) {
    return section.mapToItem(root.barRoot, section.width / 2, section.height / 2)
  }

  function sectionStart(section) {
    const point = section.mapToItem(root.barRoot, 0, 0)
    return BarContext.vertical ? point.y : point.x
  }

  function sectionSize(section) {
    return BarContext.vertical ? section.height : section.width
  }

  function clearTarget() {
    root.targetSection = ""
    root.targetIndex = -1
    root.targetValid = false
    root.indicatorRect = Qt.rect(0, 0, 0, 0)
  }

  function begin(section, index, id, x, y, barItem) {
    root.cancel()
    root.sourceId = String(id || "")
    root.sourceSection = String(section || "")
    root.sourceIndex = Number(index)
    if (root.sourceId === "" || root.sourceSection === "") return

    root.barRoot = barItem || root.barRoot
    root.active = true
    TooltipHost.clear()
    root.update(x, y)
  }

  // A new pointer position: find the gap nearest to it, across every section,
  // and describe the line that would open there.
  function update(x, y) {
    if (!root.active || !root.barRoot) return

    const vertical = BarContext.vertical
    const along = vertical ? y : x
    const across = vertical ? x : y
    const reach = (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal) + Style.space(8)
    const screenName = Screens.nameOf(root.barRoot)

    let best = null

    for (let i = 0; i < root.order.length; i++) {
      const section = root.sectionFor(screenName, root.order[i])
      if (!section) continue

      const all = section.widgets()
      const shown = []
      for (let j = 0; j < all.length; j++) {
        const loader = all[j]
        if (loader && loader.visible && loader.item) shown.push(loader)
      }

      let index = all.length
      let edge = 0
      let centre = 0

      if (shown.length === 0) {
        const point = root.sectionCentre(section)
        edge = vertical ? point.y : point.x
        centre = vertical ? point.x : point.y
      } else {
        let at = shown.length
        for (let j = 0; j < shown.length; j++) {
          const start = root.axisStart(shown[j])
          const size = vertical ? shown[j].height : shown[j].width
          if (along < start + size / 2) {
            at = j
            break
          }
        }

        if (at < shown.length) {
          index = Number(shown[at].index)
          edge = root.axisStart(shown[at]) - Theme.gap / 2
          centre = root.crossCentre(shown[at])
        } else {
          const last = shown[shown.length - 1]
          index = all.length
          edge = root.axisEnd(last) + Theme.gap / 2
          centre = root.crossCentre(last)
        }
      }

      const dx = along - edge
      const dy = across - centre
      const distance = Math.sqrt(dx * dx + dy * dy)

      // A section with a module under the pointer wins over an empty neighbour
      // even when that neighbour's gap is a few pixels closer. Without this the
      // empty centerBegin/centerEnd, which meet the centre box's edges, made
      // hovering the clock itself target them instead of the clock's own row.
      const start = root.sectionStart(section)
      const end = start + root.sectionSize(section)
      const inside = along >= start - Theme.gap / 2 && along <= end + Theme.gap / 2

      if (!best
        || (inside && !best.inside)
        || (inside === best.inside && distance < best.distance)) {
        best = {
          section: root.order[i],
          index: index,
          edge: edge,
          distance: distance,
          inside: inside,
        }
      }
    }

    if (!best || best.distance > reach) {
      root.clearTarget()
      return
    }

    // Dropping on either side of the widget's own slot is not a move, and a line
    // there would promise one.
    const sameSlot = best.section === root.sourceSection
      && (best.index === root.sourceIndex || best.index === root.sourceIndex + 1)

    root.targetSection = best.section
    root.targetIndex = best.index
    root.targetValid = !sameSlot

    if (!root.targetValid) {
      root.indicatorRect = Qt.rect(0, 0, 0, 0)
      return
    }

    const thickness = 2
    if (vertical) {
      const pos = Math.max(0, Math.min(root.barRoot.height - thickness, Math.round(best.edge - 1)))
      root.indicatorRect = Qt.rect(0, pos, root.barRoot.width, thickness)
    } else {
      const pos = Math.max(0, Math.min(root.barRoot.width - thickness, Math.round(best.edge - 1)))
      root.indicatorRect = Qt.rect(pos, 0, thickness, root.barRoot.height)
    }
  }

  function finish() {
    if (!root.active) return

    if (root.targetValid && root.sourceId !== "" && root.targetSection !== "") {
      BarConfig.move(root.sourceId, root.targetSection, root.targetIndex)
    }

    root.cancel()
  }

  function cancel() {
    root.active = false
    root.sourceId = ""
    root.sourceSection = ""
    root.sourceIndex = -1
    root.clearTarget()
  }
}
