pragma Singleton

import QtQuick
import "Ui"

// Orientation, read by the bar itself and by every module.
//
// Widgets need to know whether they are on a horizontal or a vertical bar: a
// label that fits beside an icon on a top bar has nowhere to go on a side bar,
// where the bar is only as wide as an icon. Passing this down through a
// singleton keeps it out of every module's constructor.
//
// The value comes from Theme, which Nix renders, rather than from bar.json,
// because the bar window is built once and cannot be re-anchored afterwards.
QtObject {
  property string position: Theme.position

  readonly property bool vertical: position === "left" || position === "right"

  // How far a module may run before it stops being worth showing.
  readonly property int maxBarSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
}