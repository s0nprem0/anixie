pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

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
      console.warn("bar: the bar panel could not load; status="
        + (component ? component.status : "null"))
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