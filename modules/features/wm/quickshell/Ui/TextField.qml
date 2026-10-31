import QtQuick
import QtQuick.Controls
import ".."

// A themed text input.
//
// Real QtQuick.Controls behaviour — cursor, selection, clipboard, the lot — with
// the stock chrome (its background rectangle, border, padding) replaced so it sits
// on a panel the way the rest of the shell does. Nothing here fakes text
// handling; it is a Control underneath with a styled background.
TextField {
  id: control

  implicitWidth: Style.space(180)
  implicitHeight: Math.max(Style.space(20), Style.font.body * 2)

  color: control.enabled ? Theme.fg : Theme.muted
  placeholderTextColor: Theme.muted
  selectionColor: Theme.primary
  selectedTextColor: Theme.bg
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  verticalAlignment: TextInput.AlignVCenter
  leftPadding: Style.space(10)
  rightPadding: Style.space(10)

  // The cursor follows the text colour, so it stays visible on the field's
  // background in every theme without a separate cursor colour property.
  cursorVisible: true

  Accessible.role: Accessible.EditableText
  Accessible.name: control.placeholderText
  Accessible.description: control.placeholderText

  // Quieter than the stock field, which draws a blue ring on focus — the accent
  // is enough to say where the caret is.
  background: Rectangle {
    radius: Theme.cornerRadius
    color: !control.enabled
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.5)
      : (control.activeFocus
          ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.selectedFillAlpha)
          : (control.hovered
              ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
              : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.5)))
    border.color: !control.enabled
      ? Theme.border
      : (control.readOnly
          ? Theme.border
          : (control.activeFocus
              ? Theme.primary
              : (control.hovered ? Theme.borderStrong : Theme.border)))
    border.width: Style.strokeWidth
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }
}
