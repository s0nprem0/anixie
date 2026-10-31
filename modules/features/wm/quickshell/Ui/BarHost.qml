pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

QtObject {
  id: root

  // Do not cache the component: a cached one could not be reopened a second
  // time on this Quickshell build (its status came back undefined after the
  // first use). Recreating synchronously is cheap for this small panel.
  function panelBuilder() {
    return Qt.createComponent(Qt.resolvedUrl("../panels/BarModules.qml"), Component.PreferSynchronous)
  }

  function open() {
    const anchor = PanelHost.focusedBar
    if (!anchor) return
    const component = root.panelBuilder()
    if (!component || component.status !== Component.Ready) {
      console.warn("bar: the bar panel could not load; status="
        + (component ? component.status : "null")
        + (component && typeof component.errorString === "function" ? " " + component.errorString() : ""))
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