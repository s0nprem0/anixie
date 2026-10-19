import QtQuick
import "."
import "Ui"

// One run of bar modules, as named by a bar.json section.
//
// Horizontal bars stack modules in a row; vertical ones need a column, so this
// picks its positioner from the orientation rather than forcing every module to
// know which way up the bar is.
Item {
  id: root

  // A section is part of the bar, so it goes when the bar goes. The window stays
  // mapped behind it — that is what keeps a hotkey-opened panel's anchor alive —
  // so hiding the contents is what actually makes the bar disappear.
  visible: BarContext.shown

  property var entries: []

  // Which bar.json section this is, so a module can be told which edge of itself
  // stays put when it grows. Set by shell.qml.
  property string name: ""

  readonly property bool vertical: BarContext.vertical

  // Where a scene-x would land in this section's array: before the first module
  // whose centre it has not passed, after the last one it has. Computed against
  // the modules themselves rather than their positions in the array, because a
  // hidden module has no position to compare against and still owns an index.
  function indexFor(sceneX) {
    const items = root.vertical ? column.children : row.children
    let index = 0

    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (!item || item.visible === false) continue

      const centre = item.mapToItem(null, item.width / 2, 0).x
      if (sceneX > centre) index = i + 1
    }

    return index
  }

  Component.onCompleted: BarContext.registerSection(root.name, root)

  implicitWidth: vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent

    // Modules are laid out as separate blocks rather than one continuous run.
    spacing: Theme.gap

    ModuleRepeater {
      // Empty when the row is not the orientation in use. A Repeater builds a
      // delegate for every entry in its model no matter whether its parent is
      // visible, so both orientations used to build every module twice — twice
      // the polling, and two identical buttons racing for the one shared tooltip.
      modules: !root.vertical ? root.entries : []
      sectionName: root.name
    }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Theme.gap

    ModuleRepeater {
      modules: root.vertical ? root.entries : []
      sectionName: root.name
    }
  }
}