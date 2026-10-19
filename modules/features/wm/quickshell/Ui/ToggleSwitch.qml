import QtQuick
import ".."

// A bare on/off switch: a track with a sliding knob, no label. The caller owns
// the value — bind `checked` to real state and act on `toggled()`.
//
// Square, like everything else on this bar: the track takes the theme's corner
// radius, which is 0, and the knob follows it. On a rounded theme the same code
// would give the pill switch the rest of the shell's shape without a second
// component.
//
// `busy` swallows clicks while an operation is in flight but leaves hover and
// the cursor alone, so the control does not flicker every time a background
// refresh runs.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  property color accent: Theme.accent

  property int trackHeight: Style.space(16)
  readonly property int trackWidth: Math.round(trackHeight * 1.9)
  readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.68))
  readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  signal toggled()

  // ---- the keyboard ----
  //
  // A bare switch, so the panel's Return flips it, exactly as a click would.
  readonly property bool panelFocusable: !root.busy

  function activate() {
    if (!root.busy) root.toggled()
  }

  function keyStep(direction) {
    return false
  }

  readonly property bool hot: mouse.containsMouse
  readonly property bool rounded: Theme.cornerRadius > 0

  implicitWidth: trackWidth
  implicitHeight: trackHeight

  Rectangle {
    id: track

    anchors.fill: parent
    radius: root.rounded ? height / 2 : Theme.cornerRadius

    // The same two alphas the rest of the chrome uses, so the switch reads as a
    // control at rest and as chosen when it is on — rather than inventing a third
    // fill strength for itself.
    color: root.checked
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.control.selectedFillAlpha)
      : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
    border.color: root.checked ? root.accent : Theme.muted
    border.width: 1

    Behavior on color {
      ColorAnimation { duration: Style.duration(120) }
    }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? height / 2 : Theme.cornerRadius
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? root.accent : Theme.muted

      Behavior on x {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
      Behavior on color {
        ColorAnimation { duration: Style.duration(120) }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (!root.busy) root.toggled()
  }
}
