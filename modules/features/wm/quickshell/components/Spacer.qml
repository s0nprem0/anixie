import QtQuick
import ".."
import "../Ui"

// Empty space in the bar. A module rather than a fixed margin, so a gap can be
// placed, sized and reordered from bar.json like anything else.
BarWidget {
  id: root

  // Extent along the bar. On a vertical bar the gap runs down the column, so the
  // size applies to the height instead and the width stays the bar's thickness.
  readonly property int size: {
    const n = Number(root.setting("size", 12))
    return isFinite(n) && n > 0 ? Math.round(n) : 12
  }

  implicitWidth: root.vertical ? Style.bar.sizeVertical : root.size
  implicitHeight: root.vertical ? root.size : Style.bar.sizeHorizontal
}
