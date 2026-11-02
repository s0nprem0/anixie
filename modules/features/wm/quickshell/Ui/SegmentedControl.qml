import QtQuick
import ".."

// Pick one of a few short options: a row of chips.
Item {
  id: root

  // Entries: plain strings, or { label, value } like Dropdown takes.
  property var model: []
  property int currentIndex: -1
  property bool available: true

  signal activated(int index)

  readonly property bool panelFocusable: root.available && Array.isArray(root.model) && root.model.length > 1

  function keyStep(direction) {
    if (!root.available) return false
    if (!Array.isArray(root.model) || root.model.length === 0) return false

    const dir = Number(direction)
    if (dir === 0) return false

    let from = root.currentIndex
    if (!isFinite(from) || from < 0 || from >= root.model.length) {
      from = dir > 0 ? -1 : root.model.length
    }

    let next = from + (dir > 0 ? 1 : -1)
    if (next < 0 || next >= root.model.length) {
      return false
    }

    if (next !== root.currentIndex) {
      root.activated(next)
    }
    return true
  }

  readonly property var currentEntry: {
    if (!Array.isArray(root.model) || root.model.length === 0) return null
    if (!isFinite(root.currentIndex) || root.currentIndex < 0 || root.currentIndex >= root.model.length) return null
    return root.model[root.currentIndex]
  }

  function labelFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return entry
    if (typeof entry === "object") {
      if (entry.label !== undefined && entry.label !== null) return String(entry.label)
      if (entry.value !== undefined && entry.value !== null) return String(entry.value)
    }
    return String(entry)
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
      model: Array.isArray(root.model) ? root.model : []

      delegate: Rectangle {
        id: chip
        required property int index
        required property var modelData

        readonly property bool selected: root.currentIndex === chip.index

        height: root.chipHeight
        width: Math.min(chipLabel.implicitWidth + Style.space(16), root.width > 0 ? root.width : Number.MAX_VALUE)
        radius: Theme.cornerRadius

        color: chipMouse.pressed && root.available && !chip.selected
          ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
          : (chip.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Style.control.selectedFillAlpha)
            : (chipMouse.containsMouse && root.available
              ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
              : "transparent"))
        border.color: chip.selected ? Theme.primary : Theme.border
        border.width: Style.strokeWidth
        opacity: root.available ? 1 : Style.disabledOpacity

        Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

        Text {
          id: chipLabel
          anchors.centerIn: parent
          width: parent.width - Style.space(12)
          text: root.labelFor(chip.modelData)
          color: chip.selected ? Theme.fg : Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          enabled: root.available && !chip.selected
          hoverEnabled: true
          cursorShape: root.available && !chip.selected ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (root.available) root.activated(chip.index)
        }
      }
    }
  }
}