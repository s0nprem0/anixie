import QtQuick
import ".."

// The 1px rule between panel sections.
//
// A tint of the foreground rather than a solid colour, so it sits at the same
// weight against any palette — a fixed grey would read heavy on a dark theme and
// vanish on a light one. Weak on purpose: it separates, it does not divide, and
// the panel's own border is already the loudest line on screen.
Rectangle {
  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12)
}
