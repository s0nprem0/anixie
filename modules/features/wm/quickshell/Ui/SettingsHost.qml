pragma Singleton

import QtQuick
import Quickshell
import ".."

QtObject {
  id: root

  property var panelComponent: null

  function panelBuilder() {
    if (root.panelComponent === null) {
      root.panelComponent = Qt.createComponent(Qt.resolvedUrl("../panels/Settings.qml"), Component.PreferSynchronous)
    }
    return root.panelComponent
  }

  function open() {
    const anchor = PanelHost.focusedBar
    if (!anchor) return
    const component = root.panelBuilder()
    if (!component || component.status !== Component.Ready) {
      console.warn("settings: panel could not load; status=" + (component ? component.status : "null"))
      root.panelComponent = null
      return
    }
    PanelHost.toggleNamed("settings", anchor, component)
  }

  function toggle() {
    if (PanelHost.isOpen("settings")) PanelHost.close("settings")
    else root.open()
  }

  function close() {
    PanelHost.close("settings")
  }
}
