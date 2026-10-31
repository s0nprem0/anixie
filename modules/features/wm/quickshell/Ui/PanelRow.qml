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

  // Whether a control is actually drawn in that slot.
  property bool hasControl: false

  readonly property real controlGap: Style.space(8)
  readonly property real horizontalPadding: Style.space(2)

  implicitWidth: parent ? parent.width : (Math.max(labelText.implicitWidth + Style.space(12) + valueText.implicitWidth, controlWidth))
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight, Style.space(22))

  height: implicitHeight
  clip: true

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: valueText.visible ? valueText.left : (root.hasControl ? controlSlot.left : parent.right)
    anchors.rightMargin: valueText.visible ? Style.space(6) : (root.hasControl ? root.controlGap : root.horizontalPadding)
    text: root.label
    color: Theme.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Text {
    id: valueText
    anchors.right: root.hasControl ? controlSlot.left : parent.right
    anchors.rightMargin: root.hasControl ? root.controlGap : root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    visible: root.value !== ""
    width: Math.min(implicitWidth, Math.max(40, parent.width * 0.45))
    text: root.value
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    renderType: Text.NativeRendering
    maximumLineCount: 1
  }

  // Marks the slot the control occupies
  Item {
    id: controlSlot
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(root.controlWidth, Math.max(0, parent.width - labelText.implicitWidth - Style.space(40)))
    height: root.height
    visible: false
  }
}
