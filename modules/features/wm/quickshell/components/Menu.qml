import QtQuick
import ".."
import "../Ui"

// Launcher button. Left opens the launcher, right opens a terminal — the pair
// the reference bar binds to its menu glyph. Both commands come from the layout
// entry so neither is hardcoded.
BarWidget {
  id: root

  readonly property string launcher: String(root.setting("launcher", "menu"))
  readonly property string terminal: String(root.setting("terminal", "kitty"))

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.menu
    fontSize: Style.bar.iconFont
    tooltipText: "Launcher · right-click for a terminal"

    onPressed: function (button) {
      // The default launcher is the shell's own menu, opened by a call rather
      // than by running `menu` to come back in over IPC.
      if (button === Qt.LeftButton) {
        if (root.launcher === "menu") MenuHost.open("")
        else Commands.run(root.launcher)
      }
      else if (button === Qt.RightButton) Commands.run(root.terminal)
    }
  }
}
