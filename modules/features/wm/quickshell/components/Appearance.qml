import QtQuick
import ".."
import "../Ui"

BarWidget {
  id: root

  implicitWidth: readout.implicitWidth
  implicitHeight: readout.implicitHeight

  BarIconButton {
    id: readout
    anchors.centerIn: parent
    text: Util.palette
    active: PanelHost.isOpen("appearance")
    tooltipText: "Appearance · Super+Ctrl+T"
    onPressed: function (button) {
      if (button === Qt.LeftButton || button === Qt.MiddleButton) AppearanceHost.toggle()
      else if (button === Qt.RightButton) Commands.run("wallpaper")
    }
  }
}
