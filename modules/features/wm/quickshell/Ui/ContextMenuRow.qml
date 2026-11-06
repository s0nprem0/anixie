pragma ComponentBehavior: Bound
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
  property string iconName: ""
  property string trailingIcon: ""
  property string activeIcon: ""
  property string activeText: ""
  property bool danger: false
  property bool available: true
  property bool selected: false

  signal clicked()

  Accessible.role: Accessible.MenuItem
  Accessible.name: root.label !== "" ? root.label : root.glyph

  readonly property color foreground: root.danger ? Theme.danger : Theme.fg
  readonly property bool hovered: mouse.containsMouse

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(34, Style.font.body + Style.space(12))
  height: implicitHeight

  opacity: root.available ? 1 : Style.disabledOpacity

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.pressed && root.available
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
          Style.control.pressedFillAlpha)
      : ((root.selected || root.hovered) && root.available
        ? Qt.rgba(
          root.foreground.r,
          root.foreground.g,
          root.foreground.b,
          root.selected ? Style.control.selectedFillAlpha : Style.control.hoverFillAlpha)
        : "transparent")
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    // Themed icon, when an iconName is given. Falls back to the glyph text.
    Image {
      id: iconImage
      visible: root.iconName !== ""
      width: visible ? Style.space(16) : 0
      height: width
      source: root.iconName !== "" ? (root.selected && root.activeIcon !== "" ? Quickshell.iconPath(root.activeIcon, true) : Quickshell.iconPath(root.iconName, true)) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: glyphText
      visible: root.iconName === "" && root.glyph !== ""
      width: visible ? implicitWidth : 0
      text: root.glyph
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      id: labelText
      width: Math.max(0, parent.width - (iconImage.visible ? iconImage.width + parent.spacing : 0) - (glyphText.visible ? glyphText.width + parent.spacing : 0) - (trailingText.visible ? trailingText.width + parent.spacing : 0) - (trailingIconImage.visible ? trailingIconImage.width + parent.spacing : 0))
      text: root.selected && root.activeText !== "" ? root.activeText : root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    // Trailing icon (text glyph).
    Text {
      id: trailingText
      visible: root.trailingIcon !== "" && !root.trailingIcon.startsWith("icon:")
      width: visible ? implicitWidth : 0
      text: root.trailingIcon
      color: root.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Image {
      id: trailingIconImage
      visible: root.trailingIcon !== "" && root.trailingIcon.startsWith("icon:")
      width: visible ? Style.space(14) : 0
      height: width
      source: visible ? Quickshell.iconPath(root.trailingIcon.slice(5), true) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      opacity: 0.7
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.available
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  clip: true
}
