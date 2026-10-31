pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The bar's own settings panel: position, background and the module list.
//
// Until now every one of these lived behind `anixie bar …`, so a person who
// wanted to move a widget had to leave the desktop and type. This host puts
// that surface one keypress away, the way Appearance does for the theme.
QtObject {
  id: root

  property var panelComponent: null

  function panelBuilder() {
    if (root.panelComponent === null) {
      root.panelComponent = Qt.createComponent(Qt.resolvedUrl("../panels/BarModules.qml"))
    }
    return root.panelComponent
  }

  function open() {
    const anchor = PanelHost.focusedBar
    if (!anchor) return
    const component = root.panelBuilder()
    if (!component || component.status !== Component.Ready) {
      console.warn("bar: the bar panel could not load")
      return
    }
    PanelHost.toggleNamed("bar", anchor, component)
  }

  function toggle() {
    if (PanelHost.isOpen("bar")) PanelHost.close("bar")
    else root.open()
  }

  function close() {
    PanelHost.close("bar")
  }
}