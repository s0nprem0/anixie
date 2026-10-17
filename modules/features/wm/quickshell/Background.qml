import QtQuick
import "."

// The bar's own backdrop, behind every module. Three looks, cycled by
// double-clicking empty bar space:
//
//   clear  - no fill at all, only the module blocks show
//   glassy - translucent fill; Hyprland's layer blur supplies the frosting
//   opaque - solid fill across the whole bar
//
// The choice lives in bar.json as "background". Double-clicking overrides it
// for the rest of the session; it is not written back, because QML has no
// write path for its own config.
Item {
  id: root
  anchors.fill: parent
  z: -1

  readonly property var modes: ["clear", "glassy", "opaque"]

  property string mode: BarConfig.config.background
                        ? String(BarConfig.config.background)
                        : "clear"

  function cycle() {
    const next = (modes.indexOf(mode) + 1) % modes.length
    root.mode = modes[next]
  }

  Rectangle {
    anchors.fill: parent
    visible: root.mode !== "clear"
    color: root.mode === "glassy" ? Theme.glass : Theme.bg
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onDoubleClicked: root.cycle()
  }
}