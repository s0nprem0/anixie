pragma Singleton

import QtQuick
import Quickshell
import ".."

QtObject {
  id: root

  property var panelComponent: null

  function panelBuilder() {
    if (root.panelComponent === null) {
      root.panelComponent = Qt.createComponent(Qt.resolvedUrl("../panels/NightLight.qml"), Component.PreferSynchronous)
    }
    return root.panelComponent
  }

  function open() {
    const anchor = PanelHost.focusedBar
    if (!anchor) return
    const component = root.panelBuilder()
    if (!component || component.status !== Component.Ready) {
      console.warn("nightlight: panel could not load; status=" + (component ? component.status : "null"))
      root.panelComponent = null
      return
    }
    PanelHost.toggleNamed("nightlight", anchor, component)
  }

  function toggle() {
    if (PanelHost.isOpen("nightlight")) PanelHost.close("nightlight")
    else root.open()
  }

  function close() {
    PanelHost.close("nightlight")
  }
}
EOF
echo done