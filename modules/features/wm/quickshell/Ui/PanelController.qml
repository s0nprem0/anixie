import QtQuick
import ".."

// Thin controller over PanelHost, for callers that prefer the Omarchy-style
// name. All operations delegate to the singleton; nothing is duplicated here.
QtObject {
  id: root

  function open(name, anchor, builder) {
    if (builder === undefined) PanelHost.show(name, anchor)
    else PanelHost.showNamed(name, anchor, builder)
  }

  function close(name, screenName) {
    if (name === undefined) PanelHost.closeAll()
    else PanelHost.close(name, screenName)
  }

  function toggle(name, anchor, builder) {
    if (builder === undefined) PanelHost.toggle(name, anchor)
    else PanelHost.toggleNamed(name, anchor, builder)
  }

  function isOpen(name, screenName) {
    return PanelHost.isOpen(name, screenName)
  }
}
