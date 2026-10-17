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
  readonly property bool vertical: BarContext.vertical

  implicitWidth: vertical ? Style.bar.sizeVertical : row.implicitWidth
  implicitHeight: vertical ? column.implicitHeight : Style.bar.sizeHorizontal

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: 0

    ModuleRepeater {
      modules: root.entries
    }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 0

    ModuleRepeater {
      modules: root.entries
    }
  }
}