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

  property var entries: []

  // Which bar.json section this is, so a module can be told which edge of itself
  // stays put when it grows. Set by shell.qml.
  property string name: ""

  readonly property bool vertical: BarContext.vertical

  implicitWidth: vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: 0

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
    spacing: 0

    ModuleRepeater {
      modules: root.vertical ? root.entries : []
      sectionName: root.name
    }
  }
}