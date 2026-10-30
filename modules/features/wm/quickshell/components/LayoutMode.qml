import QtQuick
import ".."
import "../Ui"

// The global tiling/floating switch, as a bar module.
//
// The mode is session-wide, so the glyph is the same on every output and in
// every section. Tiling is the resting state and is drawn quietly; floating is
// the deliberate mode, so it keeps the tinted block the other indicators use.
// Clicking is the same toggle as Super+D — there is one switch, not a second
// state the bar owns.
BarWidget {
  id: root

  readonly property bool floating: LayoutModeHost.floating

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent

    text: root.floating ? Util.floating : Util.tiling
    active: root.floating
    selected: root.floating
    dimmed: !root.floating

    tooltipText: root.floating
      ? "Floating layout · Super+D or click to tile"
      : "Tiling layout · Super+D or click to float"

    onPressed: function (button) {
      if (button === Qt.LeftButton) LayoutModeHost.toggle()
    }
  }
}
