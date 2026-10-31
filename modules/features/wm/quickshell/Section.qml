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
  property string screenName: ""

  readonly property bool vertical: BarContext.vertical

  implicitWidth: vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  // The Loaders this section is drawing, in layout order. The drag needs the
  // real items rather than the entries: a module that hides itself has no width
  // to drop beside, and the index it must write back is the entry index, which
  // is not the same as the visible item index.
  function widgets() {
    const container = root.vertical ? column : row
    const out = []

    for (let i = 0; i < container.children.length; i++) {
      const child = container.children[i]
      if (child && child.modelData !== undefined) out.push(child)
    }

    return out
  }

  Component.onCompleted: BarDrag.registerSection(root.name, root)
  Component.onDestruction: BarDrag.unregisterSection(root.name, root)

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
      screenName: root.screenName
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
      screenName: root.screenName
    }
  }
}