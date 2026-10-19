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

  color: Theme.fg
  placeholderTextColor: Theme.muted
  selectionColor: Theme.primary
  selectedTextColor: Theme.bg
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  verticalAlignment: TextInput.AlignVCenter
  leftPadding: Style.space(10)
  rightPadding: Style.space(10)

  // Quieter than the stock field, which draws a blue ring on focus — the accent
  // is enough to say where the caret is.
  background: Rectangle {
    radius: Theme.cornerRadius
    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
    border.color: control.activeFocus ? Theme.primary : Theme.muted
    border.width: 1
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
  }
}