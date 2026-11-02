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
// The choice lives in bar.json as "background". Double-clicking cycles it and
// writes the result to the saved layout, so it survives a restart — the bar owns
// a writable copy of its own config now (see BarConfig).
Item {
  id: root
  anchors.fill: parent

  // Goes with the bar. The window is left mapped so panels keep their anchor, so
  // the backdrop has to hide itself rather than rely on the window going away.
  // Its MouseArea goes too, which is what stops a hidden bar from swallowing
  // clicks along the top edge.
  visible: BarContext.shown

  readonly property var modes: ["clear", "glassy", "opaque"]

  readonly property string mode: BarConfig.config.background
                                 ? String(BarConfig.config.background)
                                 : "clear"

  // Written rather than assigned: `mode` reads the config, and assigning it here
  // would break that binding and leave the bar drawing a look the config does not
  // have.
  function cycle() {
    BarConfig.setBackground(root.modes[(root.modes.indexOf(root.mode) + 1) % root.modes.length])
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