import QtQuick
import ".."

// A row of toggle chips for choosing several items from a short list.
// Entries are { label, value } objects or plain strings. `selected` is an
// array of values (or indices when entries are strings) currently chosen;
// `toggled(index, on)` fires on a change so the caller owns the state.
Flow {
  id: root

  property var model: []
  property var selected: []
  property bool available: true

  signal toggled(int index, bool on)

  spacing: Style.space(4)

  Repeater {
    model: root.model

    delegate: Rectangle {
      id: chip
      required property var modelData
      required property int index

      readonly property bool on: {
        const sel = root.selected || []
        const value = (chip.modelData && typeof chip.modelData === "object" && !Array.isArray(chip.modelData))
          ? chip.modelData.value
          : chip.modelData
        return sel.indexOf(value) >= 0
      }

      readonly property string label: (chip.modelData && typeof chip.modelData === "object" && !Array.isArray(chip.modelData) && chip.modelData.label !== undefined)
        ? String(chip.modelData.label)
        : String(chip.modelData)

      width: chipLabel.implicitWidth + Style.space(12)
      height: Style.space(24)
      radius: Theme.cornerRadius
      color: chip.on
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
        : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
      border.width: Style.strokeWidth
      border.color: chip.on ? Theme.primary : Theme.border
      opacity: root.available ? 1 : Style.disabledOpacity

      Text {
        id: chipLabel
        anchors.centerIn: parent
        text: chip.label
        color: chip.on ? Theme.primary : Theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.weight: chip.on ? Font.DemiBold : Font.Normal
        renderType: Text.NativeRendering
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(chip.index, !chip.on)
      }
    }
  }
}
