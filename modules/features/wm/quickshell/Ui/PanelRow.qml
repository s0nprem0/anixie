import QtQuick
import ".."

// One line of a panel: a label on the left, a control on the right.
Item {
  id: root

  property string label: ""
  property string value: ""

  // Width of the slot at the right end that a control anchors into. Reserved
  // whether or not there is one, so a column of rows lines up.
  property int controlWidth: 140

  // Whether a control is actually drawn in that slot. It only decides where the
  // value goes: a row with a control has to keep the value clear of it, and a row
  // without one gives the value the right edge to itself.
  property bool hasControl: false

  readonly property real controlGap: Style.space(8)

  implicitWidth: parent ? parent.width : (labelText.implicitWidth + Style.space(12) + Math.max(valueText.implicitWidth, controlWidth))
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight, 20)

  // A Panel is a Column, and a Column positions children by their height rather
  // than their implicit height. Without this the row would take no space at all
  // and every row would stack on the same line.
  height: implicitHeight
  clip: true

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: valueText.visible ? valueText.left : (root.hasControl ? controlSlot.left : parent.right)
    anchors.rightMargin: valueText.visible ? Style.space(8) : (root.hasControl ? root.controlGap : 0)
    text: root.label
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
  }

  Text {
    id: valueText
    // Left of the control rather than on top of it. Both used to anchor to
    // parent.right, so a slider row drew the value underneath the handle — which
    // read as a clipped number rather than as a value, and only showed at all
    // where the handle happened to leave it uncovered.
    anchors.right: root.hasControl ? controlSlot.left : parent.right
    anchors.rightMargin: root.hasControl ? root.controlGap : 0
    anchors.verticalCenter: parent.verticalCenter
    visible: root.value !== ""
    width: Math.min(implicitWidth, parent.width * 0.6)
    text: root.value
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  // Marks the slot the control occupies, so the value can be placed to its left.
  // Invisible and empty: the control itself is declared by whoever uses the row,
  // and anchors to the same right edge with this width.
  Item {
    id: controlSlot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.controlWidth
    height: root.height
    visible: false
  }
}
