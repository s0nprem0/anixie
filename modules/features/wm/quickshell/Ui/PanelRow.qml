import QtQuick
import ".."

// One line of a panel: a label on the left, a control on the right.
Item {
  id: root

  property string label: ""
  property string value: ""
  property int controlWidth: 140

  implicitWidth: labelText.implicitWidth + Style.space(12) + Math.max(valueText.implicitWidth, controlWidth)
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight, 20)

  // A Panel is a Column, and a Column positions children by their height rather
  // than their implicit height. Without this the row would take no space at all
  // and every row would stack on the same line.
  height: implicitHeight

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }

  Text {
    id: valueText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.value !== ""
    text: root.value
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }
}