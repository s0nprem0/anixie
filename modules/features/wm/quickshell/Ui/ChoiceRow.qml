import QtQuick
import ".."

// A row you pick from a list: a name, an optional line under it, and the state
// that says whether it is the one in use.
//
// Four panels list something you choose between — audio outputs, wireless
// networks, bluetooth devices, the player you are listening to — and each of
// them had drawn it differently: a dot with a click target the size of a
// pixel, a hover fill, a highlighted block, a bar button. They are one control
// and they live here once, so the lists cannot drift apart again.
//
// The whole row is the target, not a glyph in it. A 8px dot with the click area
// grown around it by ten pixels is a target you have to aim at; a row that
// fills the panel is one you press.
Item {
  id: root

  property string label: ""
  property string detail: ""

  property string glyph: ""
  property color glyphColor: Theme.muted

  default property alias trailing: trailingRow.data

  property bool selected: false
  property bool available: true

  signal clicked()

  readonly property bool panelFocusable: root.available

  function activate() {
    if (root.available) root.clicked()
  }

  function keyStep(direction) {
    return false
  }

  readonly property bool hasDetail: root.detail !== ""
  readonly property bool hasGlyph: root.glyph !== ""
  readonly property real horizontalPadding: Style.space(6)

  implicitWidth: parent ? parent.width : (labelText.implicitWidth + trailingRow.implicitWidth + Style.space(40))
  implicitHeight: Math.max(textColumn.height, trailingRow.implicitHeight, Style.space(26))
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.cornerRadius
    color: mouse.pressed && root.available
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
      : (root.selected
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
            mouse.containsMouse && root.available
              ? Style.control.rowSelectedHoverAlpha
              : Style.control.selectedFillAlpha)
        : (mouse.containsMouse && root.available
          ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.rowHoverAlpha)
          : "transparent"))

    Behavior on color {
      ColorAnimation { duration: Style.duration(Style.motion.base); easing.type: Easing.OutCubic }
    }
  }

  Item {
    id: textColumn
    anchors.left: parent.left
    anchors.leftMargin: root.horizontalPadding
    anchors.right: trailingRow.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: labelText.height + (root.hasDetail ? Style.space(2) + detailText.height : 0)
    opacity: root.available ? 1 : Style.disabledOpacity

    Text {
      id: labelText
      width: parent.width - (root.hasGlyph ? glyphText.implicitWidth + Style.space(6) : 0)
      text: root.label
      color: root.selected ? Theme.accent : Theme.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: root.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
      renderType: Text.NativeRendering
      maximumLineCount: 1
    }

    Text {
      id: glyphText
      anchors.right: parent.right
      anchors.verticalCenter: labelText.verticalCenter
      visible: root.hasGlyph
      text: root.glyph
      color: root.glyphColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Text {
      id: detailText
      anchors.top: labelText.bottom
      anchors.topMargin: root.hasDetail ? Style.space(2) : 0
      width: parent.width
      visible: root.hasDetail
      text: root.detail
      color: Theme.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      renderType: Text.NativeRendering
      maximumLineCount: 1
    }
  }

  Row {
    id: trailingRow
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)
    height: implicitHeight
    opacity: root.available ? 1 : Style.disabledOpacity
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  clip: true
}