import QtQuick
import QtQuick.Controls
import ".."

// A themed slider. Real QtQuick.Controls behaviour — drag, click-to-set, wheel,
// keyboard — with the track and handle replaced so it matches the bar rather
// than the stock light chrome.
Slider {
  id: control

  readonly property color trackColour: Theme.surface
  readonly property color fillColour: Theme.primary
  readonly property color knobColour: Theme.fg
  readonly property int trackThickness: 4
  readonly property int knobRadius: 7

  implicitHeight: Math.max(knobRadius * 2, Style.space(20))

  background: Rectangle {
    x: control.leftPadding
    y: control.topPadding + control.availableHeight / 2 - height / 2
    width: control.availableWidth
    height: control.trackThickness
    radius: height / 2
    color: control.trackColour

    Rectangle {
      width: control.visualPosition * parent.width
      height: parent.height
      radius: height / 2
      color: control.fillColour
    }
  }

  handle: Rectangle {
    x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
    y: control.topPadding + control.availableHeight / 2 - height / 2
    width: control.knobRadius * 2
    height: width
    radius: width / 2
    color: control.knobColour
  }
}