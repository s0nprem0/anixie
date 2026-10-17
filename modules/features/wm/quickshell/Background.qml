import QtQuick
import "."
import "Ui"

// The bar's own backdrop, behind every module. Three looks, cycled by
// double-clicking empty bar space:
//
//   clear  - no fill at all
//   glassy - translucent fill, tinted
//   opaque - solid fill across the whole bar
//
// The choice lives in bar.json as "background". Double-clicking overrides it
// for the rest of the session; it is not written back, because QML has no
// write path for its own config.
Item {
  id: root
  anchors.fill: parent

  readonly property var modes: ["clear", "glassy", "opaque"]

  property string mode: BarConfig.config.background
                        ? String(BarConfig.config.background)
                        : "clear"

  function cycle() {
    root.mode = root.modes[(root.modes.indexOf(root.mode) + 1) % root.modes.length]
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