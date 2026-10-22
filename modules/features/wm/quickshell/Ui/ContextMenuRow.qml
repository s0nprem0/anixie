import QtQuick
import ".."

// One row of a context menu: a glyph, a label, and a click.
//
// Deliberately not PanelActionButton: a menu row is denser, never navigational,
// and has to show which row the keyboard is on without the panel's ring.
Item {
  id: root

  property string label: ""
  property string glyph: ""
  property bool danger: false
  property bool available: true
  property bool selected: false

  signal clicked()

  readonly property color foreground: root.danger ? Theme.danger : Theme.fg
  readonly property bool hovered: mouse.containsMouse

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(24, Style.font.body + Style.space(10))
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: (root.selected || root.hovered) && root.available
      ? Qt.rgba(
        root.foreground.r,
        root.foreground.g,
        root.foreground.b,
        root.selected ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
      : "transparent"
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      id: glyphText
      visible: root.glyph !== ""
      width: visible ? implicitWidth : 0
      text: root.glyph
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      opacity: root.available ? 1 : 0.45
    }

    Text {
      id: labelText
      width: Math.max(0, parent.width - glyphText.width - (glyphText.visible ? parent.spacing : 0))
      text: root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      renderType: Text.NativeRendering
      opacity: root.available ? 1 : 0.45
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.available
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
