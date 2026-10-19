import QtQuick
import ".."

// Pick one of a few short options: a row of chips, the chosen one filled.
//
// For the values that are a closed set of names rather than a range — a power
// profile, a mode, anything with three or four options too long for a switch
// and too fixed for a slider. Dropdown would work, but the whole set fits on
// one line, and a control you can see all of is one you do not have to open to
// read.
Item {
  id: root

  // Entries: plain strings, or { label, value } like Dropdown takes.
  property var model: []
  property int currentIndex: -1
  property bool available: true

  signal activated(int index)

  readonly property var currentEntry: {
    if (root.model.length === 0 || root.currentIndex < 0) return null
    return root.model[Math.min(root.currentIndex, root.model.length - 1)]
  }

  function labelFor(entry) {
    return typeof entry === "string" ? entry : String(entry && entry.label !== undefined ? entry.label : "")
  }

  readonly property int chipHeight: Style.space(24)

  implicitWidth: chips.implicitWidth
  implicitHeight: chipHeight

  Row {
    id: chips
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Repeater {
      model: root.model

      delegate: Rectangle {
        id: chip
        required property int index
        required property var modelData

        readonly property bool selected: root.currentIndex === chip.index

        height: root.chipHeight
        width: chipLabel.implicitWidth + Style.space(16)
        radius: Theme.cornerRadius

        color: chip.selected
          ? Theme.primary
          : (chipMouse.containsMouse && root.available
            ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
            : "transparent")
        border.color: chip.selected ? Theme.primary : Theme.muted
        border.width: 1
        opacity: root.available ? 1 : 0.45

        Behavior on color { NumberAnimation { duration: Style.duration(120) } }

        Text {
          id: chipLabel
          anchors.centerIn: parent
          text: root.labelFor(chip.modelData)
          color: chip.selected ? Theme.bg : Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          enabled: root.available && !chip.selected
          hoverEnabled: true
          cursorShape: root.available && !chip.selected ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activated(chip.index)
        }
      }
    }
  }
}