import QtQuick
import QtQuick.Controls
import ".."

// A themed select: the current choice on the button, a themed popup list below it.
//
// Real QtQuick.Controls Popup and ListView — dismissal, keyboard, focus handling
// — with the stock menu chrome replaced so it matches the shell. The popup closes
// on the outside click the way it should and reports the chosen entry.
//
// Entries are { label, value } objects, or plain strings. `currentIndex` is the
// selected row; `activated(index)` fires on a pick.
Item {
  id: root

  // Entries: array of { label: string, value: any } or plain strings.
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
  property string filterText: ""

  signal activated(int index)

  // ---- the keyboard ----
  //
  // Return opens the list, and the list then takes the keyboard itself — arrows
  // walk the entries, Return picks one, Escape puts it away — which is Qt's own
  // popup doing what it already knows how to do. The sideways keys step the
  // choice without opening anything, for when the answer is "the next one".
  readonly property bool interactive: root.available
  readonly property bool panelFocusable: root.available && root.model.length > 0

  function activate() {
    if (!root.available || !Array.isArray(root.model) || root.model.length === 0) return
    if (list.opened) list.close()
    else list.open()
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

  // Filtered view of the model when searchable. Plain strings and {label,value}
  // objects are both supported; matching is case-insensitive on the label.
  readonly property var filteredModel: {
    if (!root.searchable || root.filterText.trim() === "") return root.model
    const q = root.filterText.trim().toLowerCase()
    const out = []
    if (!Array.isArray(root.model)) return root.model
    for (let i = 0; i < root.model.length; i++) {
      const entry = root.model[i]
      const label = root.labelFor(entry).toLowerCase()
      if (label.indexOf(q) >= 0) out.push(entry)
    }
    return out
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

  // (currentLabel is defined above with labelFor)

  function labelFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return entry
    if (typeof entry !== "object" || Array.isArray(entry)) return ""
    if (entry.label === undefined || entry.label === null) return ""
    return String(entry.label)
  }

  implicitWidth: Style.space(160)
  implicitHeight: Style.space(26)
  height: implicitHeight
  opacity: root.available ? 1 : Style.disabledOpacity

  onAvailableChanged: {
    if (!root.available && list.opened) list.close()
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.pressed && root.available
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
      : (mouse.containsMouse && root.available
        ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
        : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.5))
    border.color: list.opened || (mouse.containsMouse && root.available) ? Theme.primary : Theme.border
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
    onClicked: list.opened ? list.close() : list.open()
  }

  Popup {
    id: list
    parent: root
    implicitHeight: Math.min(listContent.implicitHeight, list.maxHeight)
    padding: 0
    modal: false
    focus: true

    property bool flipped: false

    property bool updating: false
    property int maxHeight: Style.space(260)

    function updatePosition() {
      if (list.updating) return
      list.updating = true

      const spacing = Style.space(4)
      const maxH = Style.space(260)
      const contentH = listContent.implicitHeight || 0
      const rootPos = root.mapToGlobal(0, 0)
      const screen = root.Window && root.Window.screen ? root.Window.screen : null
      const screenX = screen ? screen.x : 0
      const screenY = screen ? screen.y : 0
      const screenW = screen ? screen.width : (root.Window ? root.Window.width : 0)
      const screenH = screen ? screen.height : (root.Window ? root.Window.height : 0)

      const spaceBelow = screenH > 0 ? (screenY + screenH - (rootPos.y + root.height) - spacing) : contentH
      const spaceAbove = screenH > 0 ? (rootPos.y - screenY - spacing) : contentH

      let width = root.width
      if (screenW > 0) width = Math.min(width, screenW - spacing * 2)
      if (width < 1) width = 1
      list.width = width

      // Horizontal placement in root's coordinate space.
      let x = 0
      const overflowRight = (rootPos.x + width + spacing) - (screenX + screenW)
      if (overflowRight > 0) {
        x = -Math.min(overflowRight, rootPos.x - screenX - spacing)
      }
      list.x = Math.round(x)

      // Available height on the better side.
      const available = Math.max(spaceBelow, spaceAbove)
      list.maxHeight = Math.max(Style.space(40), Math.min(maxH, available > 0 ? available : maxH))

      const popupH = Math.min(contentH, list.maxHeight)
      let y = root.height + spacing
      let flip = false
      if (popupH > spaceBelow && spaceAbove >= popupH) {
        y = -(popupH + spacing)
        flip = true
      } else if (popupH > spaceBelow && spaceAbove > spaceBelow) {
        y = -(popupH + spacing)
        flip = true
      }
      // Clamp vertical position to the window bounds.
      const minY = screenY - rootPos.y + spacing
      const maxY = screenY + screenH - rootPos.y - popupH - spacing
      if (y < minY) y = minY
      if (y > maxY && maxY >= minY) y = maxY

      list.y = Math.round(y)
      list.flipped = flip
      list.updating = false
    }

    Component.onCompleted: updatePosition()
    onAboutToShow: updatePosition()
    Connections {
      target: listContent
      function onImplicitHeightChanged() { if (list.opened) list.updatePosition() }
    }
    Connections {
      target: root
      function onXChanged() { if (list.opened) list.updatePosition() }
      function onYChanged() { if (list.opened) list.updatePosition() }
      function onWidthChanged() { if (list.opened) list.updatePosition() }
      function onHeightChanged() { if (list.opened) list.updatePosition() }
      function onModelChanged() {
        if (list.opened) {
          if (list.highlighted < 0 || list.highlighted >= root.model.length) {
            list.highlighted = root.model.length === 0 ? -1 : (root.currentIndex >= 0 ? root.currentIndex : 0)
          }
          list.updatePosition()
        }
      }
      function onFilterTextChanged() {
        if (list.opened) list.updatePosition()
      }
      function onAvailableChanged() {
        if (!root.available && list.opened) list.close()
      }
    }

    // Which row the keyboard is on while the popup is up. Kept separate from
    // `root.currentIndex`: that one belongs to the caller's binding, and
    // writing it from here would replace the binding and stop the control
    // following the value it is meant to show.
    property int highlighted: -1

    function moveHighlight(delta) {
      if (!Array.isArray(root.model) || root.model.length === 0) return
      let from = list.highlighted
      if (from < 0) from = delta > 0 ? -1 : root.model.length
      let next = from + delta
      while (next >= 0 && next < root.model.length) {
        if (root.isEnabled(next) && (function () {
          if (!root.searchable) return true
          const q = root.filterText.trim().toLowerCase()
          if (q === "") return true
          return root.labelFor(root.model[next]).toLowerCase().indexOf(q) >= 0
        })()) break
        next += delta > 0 ? 1 : -1
      }
      next = Math.max(0, Math.min(root.model.length - 1, next))
      if (!root.isEnabled(next)) return
      if (root.searchable) {
        const q = root.filterText.trim().toLowerCase()
        if (q !== "" && root.labelFor(root.model[next]).toLowerCase().indexOf(q) < 0) return
      }
      list.highlighted = next
      listContent.positionViewAtIndex(next, ListView.Contain)
    }

    function choose() {
      const chosen = list.highlighted
      if (chosen < 0 || chosen >= root.model.length || !root.isEnabled(chosen)) return
      // Close before reporting the choice: the caller may rebuild the model
      // this dropdown is part of (a module moving sections, a screen change),
      // which would destroy the popup and leave `list` undefined below.
      list.close()
      root.activated(chosen)
    }

    // The list can be longer than the popup — nineteen modes on one monitor —
    // and a ListView starts at the top. Opening at the current entry is what
    // makes the control say what is selected without a scroll first.
    onOpened: {
      root.filterText = ""
      updatePosition()
      if (!Array.isArray(root.model) || root.model.length === 0) {
        list.highlighted = -1
      } else {
        let idx = root.currentIndex >= 0 ? root.currentIndex : 0
        if (idx >= root.model.length) idx = root.model.length - 1
        if (!root.isEnabled(idx) || (root.searchable && root.filterText.trim() !== "" && root.labelFor(root.model[idx]).toLowerCase().indexOf(root.filterText.trim().toLowerCase()) < 0)) {
          // find first enabled matching
          idx = -1
          const q = root.searchable ? root.filterText.trim().toLowerCase() : ""
          for (let i = 0; i < root.model.length; i++) {
            if (!root.isEnabled(i)) continue
            if (q !== "" && root.labelFor(root.model[i]).toLowerCase().indexOf(q) < 0) continue
            idx = i
            break
          }
        }
        list.highlighted = idx
      }
      listContent.forceActiveFocus()
      Qt.callLater(function () {
        if (list.highlighted >= 0) {
          listContent.positionViewAtIndex(list.highlighted, ListView.Contain)
        }
      })
    }

    onClosed: {
      list.highlighted = -1
      // Hand the keyboard back to the panel rather than leaving it on a hidden
      // list; the panel's own key handling then continues from the same stop.
      root.forceActiveFocus()
    }

    background: Rectangle {
      color: Theme.surface
      radius: Theme.cornerRadius
      // A floating surface sits above the panel, so its edge is one step
      // stronger than the card's.
      border.color: Theme.borderStrong
      border.width: Style.strokeWidth
    }

    enter: Transition {
      NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.duration(120) }
    }
    exit: Transition {
      NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Style.duration(100) }
    }

    contentItem: Column {
      id: listColumn
      spacing: 0

      TextField {
        id: filterField
        visible: root.searchable
        width: parent.width
        height: visible ? Style.space(28) : 0
        placeholderText: "Filter…"
        text: root.filterText
        onTextChanged: root.filterText = text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: Theme.fg
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
      }

      ListView {
        id: listContent
        width: parent.width
        clip: true
        implicitHeight: contentHeight
        model: root.model
        ScrollBar.vertical: ScrollBar {}
      currentIndex: list.highlighted
      boundsBehavior: Flickable.StopAtBounds
      focus: true

      // The popup takes the keyboard so the panel cannot walk away from the
      // list being chosen. These are the list's own keys; the panel sees none
      // of them until the popup closes.
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Down) {
          list.moveHighlight(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          list.moveHighlight(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
          list.choose()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          list.close()
          event.accepted = true
        }
      }

      delegate: Rectangle {
        id: row
        width: ListView.view.width
        required property int index
        required property var modelData

        readonly property bool highlighted: row.index === list.highlighted
        readonly property bool committed: row.index === root.currentIndex
        readonly property bool matches: {
          if (!root.searchable) return true
          const q = root.filterText.trim().toLowerCase()
          if (q === "") return true
          return root.labelFor(row.modelData).toLowerCase().indexOf(q) >= 0
        }
        visible: row.matches
        height: row.matches ? Style.space(32) : 0

        color: !root.isEnabled(row.index)
          ? "transparent"
          : (rowMouse.pressed
            ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
            : (row.highlighted
              ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Style.control.selectedFillAlpha)
              : (rowMouse.containsMouse
                ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
                : "transparent")))

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: checkmark.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: root.labelFor(row.modelData)
          color: root.isEnabled(row.index) ? Theme.fg : Theme.muted
          opacity: root.isEnabled(row.index) ? 1 : Style.disabledOpacity
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          id: checkmark
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          visible: row.committed
          text: "✓"
          color: Theme.primary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.isEnabled(row.index)
          cursorShape: root.isEnabled(row.index) ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (!root.isEnabled(row.index)) return
            // Only the choice is reported; `currentIndex` is the caller's to set.
            // Writing it here would replace whatever binding put it there, and the
            // dropdown would then stop following the value it was meant to be
            // showing — the same trap a stepper falls into.
            // Close first: the caller may rebuild this dropdown's model.
            list.close()
            root.activated(row.index)
          }
        }
      }
      }
    }
  }
}