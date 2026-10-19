import QtQuick
import ".."

// A panel row you can click. Looks like a PanelRow — a label on the left, a value
// on the right — but the whole row is the button, with the row's hover fill to
// say so.
//
// Panels use this for the rows that lead somewhere or do something rather than
// showing a value: "Sign out", "Turn off Wi-Fi", "Open settings". A plain
// PanelRow looks identical until you move the pointer over it, which is the
// problem this solves.
Item {
  id: root

  property string label: ""
  property string value: ""
  property string glyph: ""
  property bool danger: false

  signal clicked()

  readonly property color foreground: root.danger ? Theme.danger : Theme.fg

  implicitWidth: labelText.implicitWidth + Style.space(12) + valueText.implicitWidth + Style.space(10) + chevron.implicitWidth
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight, 20)

  // A Panel is a Column, which positions children by height rather than implicit
  // height. Without this the row takes no space and every row stacks on one line.
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, Style.control.hoverFillAlpha)
      : "transparent"
    Behavior on color { NumberAnimation { duration: Style.duration(120) } }
  }

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.right: valueText.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
  }

  Text {
    id: valueText
    anchors.right: chevron.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.value !== ""
    text: root.value
    color: Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
    elide: Text.ElideLeft
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: "›"
    color: mouse.containsMouse ? root.foreground : Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    Behavior on color { NumberAnimation { duration: Style.duration(120) } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}