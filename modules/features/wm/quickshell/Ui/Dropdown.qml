import QtQuick
import ".."

// A themed select: the current choice on the button, a themed popup list below it.
//
// The list itself lives in DropdownHost, in a layer surface of its own. A panel
// is a layer surface sized to its card, and a popup drawn inside that surface is
// clipped by the panel window at the card's edge. The host's window is on the
// Overlay layer instead, so the list can extend past the panel.
//
// Entries are { label, value } objects, or plain strings. `currentIndex` is the
// selected row; `activated(index)` fires on a pick.
Item {
  id: root

  // Entries: array of { label, value: any } or plain strings.
  property var model: []
  property int currentIndex: -1
  property string placeholder: ""

  // Whether the dropdown takes input at all. A screen that is mirroring has no
  // geometry of its own to change, and a value the caller is still writing
  // should not be changed under it; both use this rather than a live control
  // that silently does nothing.
  property bool available: true

  // When true, the popup shows a filter field at the top so long lists (DNS
  // providers, bands, …) can be narrowed without scrolling.
  property bool searchable: false

  // Optional width constraints for the popup. Zero means "no constraint", so
  // the popup is as wide as the control by default.
  property int popupMinWidth: 0
  property int popupMaxWidth: 0

  signal activated(int index)

  // Mirrors the host's state for the button border. Kept as a plain property
  // rather than a binding so that merely loading a Dropdown does not touch the
  // DropdownHost singleton: the host is built at shell startup, not from inside
  // a panel that is still constructing.
  property bool listOpened: false

  // ---- the keyboard ----
  //
  // Return opens the list, and the list then takes the keyboard itself — arrows
  // walk the entries, Return picks one, Escape puts it away. The sideways keys
  // step the choice without opening anything, for when the answer is "the next
  // one".
  readonly property bool interactive: root.available
  readonly property bool panelFocusable: root.available && root.model.length > 0

  function activate() {
    if (!root.available || !Array.isArray(root.model) || root.model.length === 0) return
    if (root.listOpened) DropdownHost.close()
    else if (DropdownHost.open(root)) root.listOpened = true
  }

  // Called by the host when the list closes, whichever way it was dismissed.
  function dropdownClosed() {
    root.listOpened = false
  }

  function isEnabled(index) {
    if (index < 0 || index >= root.model.length) return false
    const entry = root.model[index]
    return !(entry && typeof entry === "object" && entry.disabled === true)
  }

  function keyStep(direction) {
    if (!root.available || !Array.isArray(root.model) || root.model.length === 0) return false

    let from = root.currentIndex
    if (from < 0) from = direction > 0 ? -1 : root.model.length
    let next = from + direction
    // Skip disabled entries and clamp to the valid range.
    while (next >= 0 && next < root.model.length && !root.isEnabled(next)) next += direction > 0 ? 1 : -1
    next = Math.max(0, Math.min(root.model.length - 1, next))
    if (root.isEnabled(next) && next !== root.currentIndex) root.activated(next)

    // The key stays here whether or not it moved anything: at the end of the
    // list there is nowhere to go, and handing it back to the panel would walk
    // the focus off the thing being chosen.
    return true
  }

  function labelFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return entry
    if (typeof entry !== "object" || Array.isArray(entry)) return ""
    if (entry.label === undefined || entry.label === null) return ""
    return String(entry.label)
  }

  readonly property var currentEntry: {
    if (!Array.isArray(root.model) || root.model.length === 0) return null
    if (root.currentIndex < 0 || root.currentIndex >= root.model.length) return null
    const entry = root.model[root.currentIndex]
    if (entry === null || entry === undefined) return null
    return typeof entry === "string" ? { label: entry, value: entry } : entry
  }

  readonly property string currentLabel: {
    if (root.currentEntry) {
      const label = root.labelFor(root.currentEntry)
      return label !== "" ? label : root.placeholder
    }
    return root.placeholder
  }

  implicitWidth: Style.space(160)
  implicitHeight: Style.space(26)
  height: implicitHeight
  opacity: root.available ? 1 : Style.disabledOpacity

  onAvailableChanged: {
    if (!root.available) DropdownHost.closeFor(root)
  }

  // The host has its own copy of the transient list state so it can stay open
  // while the caller rebuilds the model behind it.
  Connections {
    target: root
    function onModelChanged() { DropdownHost.refresh(root) }
    function onCurrentIndexChanged() { DropdownHost.refresh(root) }
    function onSearchableChanged() { DropdownHost.refresh(root) }
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.pressed && root.available
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
      : (mouse.containsMouse && root.available
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
        : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.5))
    border.color: root.listOpened || (mouse.containsMouse && root.available) ? Theme.primary : Theme.border
    border.width: Style.strokeWidth
    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: chevron.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.currentLabel
    color: root.currentEntry ? Theme.fg : Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: "⌄"
    color: mouse.containsMouse && root.available ? Theme.primary : Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.available
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activate()
  }
}
