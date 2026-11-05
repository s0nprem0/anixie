pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import ".."

// The list every Dropdown opens, owned here rather than by each control.
//
// A panel is a layer surface sized to its card, so a popup drawn inside it is
// clipped by the panel window at the card's edge. The list therefore lives in
// a layer surface of its own, on the Overlay layer, which can extend past the
// panel. Only one select can be open at a time, so one shared surface is
// enough: the Dropdown hands over its model and selection, and gets
// `activated` back on a pick.
//
// The surface covers the whole screen while it is up. That is what dismisses
// the list on a click anywhere outside the card, without a second curtain
// window. Positioning uses the panel's own placement (PanelHost) plus the
// control's position inside it, because under Wayland a surface does not know
// its own global position.
QtObject {
  id: root

  // The Dropdown that opened the list, and the values copied from it. The list
  // is transient and the caller owns the real selection, so a copy is enough;
  // refresh() below keeps it in step when the model changes underneath.
  property var target: null
  property var model: []
  property int currentIndex: -1
  property bool searchable: false
  property string filterText: ""

  // Optional width constraints copied from the opening control.
  property int minWidth: 0
  property int maxWidth: 0

  property bool opened: false
  property int highlighted: -1
  property bool flipped: false

  // Monotonic id for the currently open session. Async callbacks capture it
  // and bail out if a newer session has started, so a stale close/focus
  // restore cannot touch the new dropdown.
  property int openGeneration: 0

  // Where the card sits inside the full-screen surface, and how big it is.
  property int cardX: 0
  property int cardY: 0
  property int cardWidth: Style.space(160)
  property int cardHeight: 0

  readonly property int rowHeight: Style.space(32)
  readonly property int filterHeight: root.searchable ? Style.space(28) : 0
  readonly property int contentHeight: {
    if (!Array.isArray(root.model)) return root.filterHeight
    let h = root.filterHeight
    for (let i = 0; i < root.model.length; i++) {
      if (root.matchesIndex(i)) h += root.rowHeightFor(i)
    }
    return h
  }
  readonly property int maxHeight: Style.space(260)

  // Forces the singleton, and with it the window, to exist at shell load rather
  // than on the first click. Reading it from shell.qml is what pins the
  // lifetime to the shell instead of to whichever panel opened first.
  readonly property bool ready: true

  function isEnabled(index) {
    if (index < 0 || index >= root.model.length) return false
    const entry = root.model[index]
    return !(entry && typeof entry === "object" && entry.disabled === true)
  }

  function labelFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return entry
    if (typeof entry !== "object" || Array.isArray(entry)) return ""
    if (entry.label === undefined || entry.label === null) return ""
    return String(entry.label)
  }

  function descriptionFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return ""
    if (typeof entry !== "object" || Array.isArray(entry)) return ""
    if (entry.description === undefined || entry.description === null) return ""
    return String(entry.description)
  }

  function iconFor(entry) {
    if (entry === null || entry === undefined) return ""
    if (typeof entry === "string") return ""
    if (typeof entry !== "object" || Array.isArray(entry)) return ""
    if (entry.icon === undefined || entry.icon === null) return ""
    return String(entry.icon)
  }

  function rowHeightFor(index) {
    if (index < 0 || index >= root.model.length) return root.rowHeight
    return root.descriptionFor(root.model[index]) !== ""
      ? Style.space(48)
      : root.rowHeight
  }

  function matchesIndex(index) {
    if (index < 0 || index >= root.model.length) return false
    if (!root.searchable) return true
    const q = root.filterText.trim().toLowerCase()
    if (q === "") return true
    return root.labelFor(root.model[index]).toLowerCase().indexOf(q) >= 0
  }

  readonly property int visibleCount: {
    if (!Array.isArray(root.model)) return 0
    if (!root.searchable || root.filterText.trim() === "") return root.model.length
    let count = 0
    for (let i = 0; i < root.model.length; i++) {
      if (root.matchesIndex(i)) count += 1
    }
    return count
  }

  function targetAlive() {
    if (!root.target) return false
    try {
      return root.target.width !== undefined
    } catch (e) {
      return false
    }
  }

  // The panel that owns the control, if it is still open. Its stored screen
  // position is the only reliable origin under Wayland.
  function ownerEntry() {
    if (!root.targetAlive()) return null
    let key = null
    let cur = root.target
    while (cur) {
      if (cur.panelKey !== undefined && cur.panelKey !== null) {
        key = cur.panelKey
        break
      }
      cur = cur.parent
    }
    if (!key) return null
    try {
      return PanelHost.entries[key] || null
    } catch (e) {
      return null
    }
  }

  function targetShown() {
    if (!root.targetAlive()) return false
    try {
      const entry = root.ownerEntry()
      // Panels register themselves asynchronously; until an entry exists, trust
      // that the control is still on screen rather than closing the list.
      if (!entry) return true
      const item = entry.contentItem
      if (item && item.Window && item.Window.window)
        return item.Window.window.visible
      return true
    } catch (e) {
      return true
    }
  }

  function targetScreenPos() {
    // Returns { x, y } of the control relative to its screen, or null.
    if (!root.targetAlive()) return null
    const entry = root.ownerEntry()
    if (!entry) return null

    let screenX = entry.screenX
    let screenY = entry.screenY
    // Fall back to computing the panel's place on demand if the stored values
    // have not been populated yet (early open, or a panel that opened without
    // running syncEntry).
    if (screenX === undefined || screenY === undefined) {
      const anchor = entry.anchor
      const screenName = entry.screenName
      const win = entry.window
      const w = (win && win.implicitWidth) ? win.implicitWidth : 340
      const h = (win && win.implicitHeight) ? win.implicitHeight : 0
      try {
        screenX = PanelHost.panelX(anchor, w, screenName)
        screenY = PanelHost.panelY(anchor, h, screenName)
      } catch (e) {
        return null
      }
    }

    let localX = 0
    let localY = 0
    const contentItem = entry.contentItem
    if (contentItem) {
      try {
        const p = root.target.mapToItem(contentItem, 0, 0)
        localX = p.x
        localY = p.y
      } catch (e) {
      }
    }

    return { x: screenX + localX, y: screenY + localY }
  }

  function _fallbackScreen() {
    if (Screens.focused) return Screens.focused
    if (Quickshell.screens && Quickshell.screens.length > 0) return Quickshell.screens[0]
    return null
  }

  function targetScreenWidth() {
    return (root.targetScreen && root.targetScreen.width) ? root.targetScreen.width : 1
  }

  function targetScreenHeight() {
    return (root.targetScreen && root.targetScreen.height) ? root.targetScreen.height : 1
  }

  readonly property var targetScreen: {
    if (!root.target) return root._fallbackScreen()
    const screen = Screens.byName(Screens.nameOf(root.target))
    return screen !== null ? screen : root._fallbackScreen()
  }

  function open(dropdown) {
    if (!dropdown || !dropdown.available) return false
    if (!Array.isArray(dropdown.model) || dropdown.model.length === 0) return false

    const previous = root.target
    const wasOpen = root.opened
    if (wasOpen && previous && previous !== dropdown) {
      try {
        previous.dropdownClosed()
      } catch (e) {
      }
    }

    root.target = dropdown
    root.model = dropdown.model
    root.currentIndex = dropdown.currentIndex
    root.searchable = dropdown.searchable
    root.minWidth = dropdown.popupMinWidth
    root.maxWidth = dropdown.popupMaxWidth
    root.filterText = ""
    root.openGeneration += 1
    root.updatePosition()
    if (!wasOpen) root.opened = true
    else root.prepareHighlight()
    return true
  }

  function closeFor(dropdown) {
    if (root.target === dropdown) root.close()
  }

  function refresh(dropdown) {
    if (!root.opened || root.target !== dropdown) return
    if (!Array.isArray(dropdown.model) || dropdown.model.length === 0) {
      root.close()
      return
    }
    root.model = dropdown.model
    root.currentIndex = dropdown.currentIndex
    root.searchable = dropdown.searchable
    root.minWidth = dropdown.popupMinWidth
    root.maxWidth = dropdown.popupMaxWidth
    root.updatePosition()
  }

  function close() {
    if (!root.opened) return
    root.opened = false
  }

  // The list can be longer than the screen, so it is capped and scrolled. The
  // card is placed below the control, above it when that is the roomier side,
  // and slid sideways to stay on screen. Positioning uses the panel's stored
  // screen origin because under Wayland a surface does not know its own.
  function updatePosition() {
    if (!root.targetAlive()) return

    const screen = root.targetScreen
    if (!screen) return

    const pos = root.targetScreenPos()
    const originX = pos ? pos.x : 0
    const originY = pos ? pos.y : 0

    const spacing = Style.space(4)
    const screenW = Math.max(1, Math.round(screen.width))
    const screenH = Math.max(1, Math.round(screen.height))

    let width = Math.min(root.target.width, screenW - spacing * 2)
    if (root.minWidth > 0) width = Math.max(width, root.minWidth)
    if (root.maxWidth > 0) width = Math.min(width, root.maxWidth)
    if (width > screenW - spacing * 2) width = screenW - spacing * 2
    if (width < 1) width = 1
    let x = originX
    if (x + width > screenW - spacing) x = screenW - spacing - width
    if (x < spacing) x = spacing

    const spaceBelow = screenH - (originY + root.target.height) - spacing
    const spaceAbove = originY - spacing
    const flip = root.contentHeight > spaceBelow && spaceAbove > spaceBelow
    const available = Math.max(spacing, flip ? spaceAbove : spaceBelow)
    const height = Math.max(1, Math.min(root.contentHeight, root.maxHeight, available))

    let y = flip ? (originY - height - spacing) : (originY + root.target.height + spacing)
    if (y < spacing) y = spacing
    if (y + height > screenH - spacing) y = Math.max(spacing, screenH - spacing - height)

    root.cardX = Math.round(x)
    root.cardY = Math.round(y)
    root.cardWidth = Math.round(width)
    root.cardHeight = Math.round(height)
    root.flipped = flip
  }

  function prepareHighlight() {
    if (!Array.isArray(root.model) || root.model.length === 0) {
      root.highlighted = -1
      return
    }

    let index = root.currentIndex >= 0 ? root.currentIndex : 0
    if (index >= root.model.length) index = root.model.length - 1
    if (!root.isEnabled(index) || !root.matchesIndex(index)) {
      index = -1
      for (let i = 0; i < root.model.length; i++) {
        if (root.isEnabled(i) && root.matchesIndex(i)) {
          index = i
          break
        }
      }
    }
    root.highlighted = index
  }

  function moveHighlight(delta) {
    if (!Array.isArray(root.model) || root.model.length === 0) return
    let from = root.highlighted
    if (from < 0) from = delta > 0 ? -1 : root.model.length
    let next = from + delta
    while (next >= 0 && next < root.model.length) {
      if (root.isEnabled(next) && root.matchesIndex(next)) break
      next += delta > 0 ? 1 : -1
    }
    next = Math.max(0, Math.min(root.model.length - 1, next))
    if (!root.isEnabled(next) || !root.matchesIndex(next)) return
    root.highlighted = next
    listContent.positionViewAtIndex(next, ListView.Contain)
  }

  function choose() {
    const chosen = root.highlighted
    const dropdown = root.target
    const gen = root.openGeneration
    if (chosen < 0 || chosen >= root.model.length || !root.isEnabled(chosen)) return
    root.close()
    if (gen !== root.openGeneration) return
    if (dropdown) dropdown.activated(chosen)
  }

  onFilterTextChanged: {
    if (!root.opened) return
    root.prepareHighlight()
    Qt.callLater(function () {
      if (root.opened) root.updatePosition()
    })
  }

  onOpenedChanged: {
    if (root.opened) {
      root.updatePosition()
      root.prepareHighlight()
      const gen = root.openGeneration
      Qt.callLater(function () {
        if (gen !== root.openGeneration) return
        if (!root.opened) return
        if (root.searchable) filterField.forceActiveFocus()
        else listContent.forceActiveFocus()
        if (root.highlighted >= 0) listContent.positionViewAtIndex(root.highlighted, ListView.Contain)
      })
    } else {
      const dropdown = root.target
      const gen = root.openGeneration
      root.highlighted = -1
      root.target = null
      root.model = []
      root.filterText = ""
      if (dropdown) {
        try {
          dropdown.dropdownClosed()
        } catch (e) {
        }
      }
      Qt.callLater(function () {
        if (gen !== root.openGeneration) return
        if (!dropdown) return
        try {
          if (dropdown.visible) dropdown.forceActiveFocus()
        } catch (e) {
        }
      })
    }
  }

  // The panel under the list can scroll, which moves the control without
  // changing any of its own properties. Re-place it while it is up.
  property Timer positionTimer: Timer {
    interval: 80
    repeat: true
    running: root.opened
    onTriggered: {
      if (!root.targetShown()) {
        root.close()
        return
      }
      root.updatePosition()
    }
  }

  // Full-screen curtain on every output while a list is open: a click anywhere
  // outside the card closes it, including on monitors that the list's own
  // surface does not cover.
  property Curtain curtain: Curtain {
    screens: root.opened ? Screens.all : []
    layer: WlrLayer.Overlay
    namespace: "quickshell-dropdown-curtain"
    keyboardFocus: WlrKeyboardFocus.None
    onPressed: function (screenName) { root.close() }
  }

  property PanelWindow window: PanelWindow {
    id: list

    screen: root.targetScreen
    visible: (root.opened === true) && (root.target !== null) && (root.targetAlive() === true)
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: root.targetScreenWidth()
    implicitHeight: root.targetScreenHeight()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-dropdown"
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    // The click-catcher. A select is transient: the next click anywhere closes
    // it without reaching whatever was underneath.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: root.close()
    }

    PopupCard {
      id: card

      x: root.cardX
      y: root.cardY
      width: root.cardWidth
      height: root.cardHeight
      borderColor: Theme.borderStrong

      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }

      // Keep clicks on the card's own background from reaching the dismiss
      // area behind it. Clicks on rows and the filter field land on their own
      // controls above this.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Column {
        id: listColumn
        anchors.fill: parent
        spacing: 0

        TextField {
          id: filterField
          visible: root.searchable
          width: parent.width
          height: visible ? root.filterHeight : 0
          placeholderText: "Filter…"
          text: root.filterText
          onTextChanged: root.filterText = text
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Down) {
              root.moveHighlight(1)
              listContent.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.choose()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            }
          }
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
          height: Math.max(0, card.height - root.filterHeight - (noResults.visible ? noResults.implicitHeight : 0))
          clip: true
          implicitHeight: contentHeight
          model: root.model
          ScrollBar.vertical: ScrollBar {}
          currentIndex: root.highlighted
          boundsBehavior: Flickable.StopAtBounds
          focus: true

          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Home) {
              let first = -1
              for (let i = 0; i < root.model.length; i++) {
                if (root.isEnabled(i) && root.matchesIndex(i)) { first = i; break }
              }
              if (first >= 0) root.highlighted = first
              event.accepted = true
            } else if (event.key === Qt.Key_End) {
              let last = -1
              for (let i = root.model.length - 1; i >= 0; i--) {
                if (root.isEnabled(i) && root.matchesIndex(i)) { last = i; break }
              }
              if (last >= 0) root.highlighted = last
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.moveHighlight(5)
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.moveHighlight(-5)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              root.moveHighlight(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              // Up from the first match returns to the search field, mirroring
              // Omarchy's behaviour, so the keyboard never gets stuck at the top.
              let first = -1
              for (let i = 0; i < root.model.length; i++) {
                if (root.isEnabled(i) && root.matchesIndex(i)) { first = i; break }
              }
              if (root.searchable && (root.highlighted < 0 || root.highlighted === first)) {
                filterField.forceActiveFocus()
              } else {
                root.moveHighlight(-1)
              }
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                       || event.key === Qt.Key_Space) {
              root.choose()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            }
          }

          delegate: Rectangle {
            id: row
            width: ListView.view.width
            required property int index
            required property var modelData

            readonly property bool highlighted: row.index === root.highlighted
            readonly property bool committed: row.index === root.currentIndex
            readonly property bool matches: root.matchesIndex(row.index)
            visible: row.matches
            height: row.matches ? root.rowHeightFor(row.index) : 0

            color: !root.isEnabled(row.index)
              ? "transparent"
              : (rowMouse.pressed
                ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.pressedFillAlpha)
                : (row.highlighted
                  ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Style.control.selectedFillAlpha)
                  : (rowMouse.containsMouse
                    ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
                    : "transparent")))

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: checkmark.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                visible: root.iconFor(row.modelData) !== ""
                text: root.iconFor(row.modelData)
                color: root.isEnabled(row.index) ? Theme.fg : Theme.muted
                opacity: root.isEnabled(row.index) ? 1 : Style.disabledOpacity
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - (root.iconFor(row.modelData) !== "" ? Style.space(20) : 0)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: root.labelFor(row.modelData)
                  color: root.isEnabled(row.index) ? Theme.fg : Theme.muted
                  opacity: root.isEnabled(row.index) ? 1 : Style.disabledOpacity
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }

                Text {
                  width: parent.width
                  visible: root.descriptionFor(row.modelData) !== ""
                  text: root.descriptionFor(row.modelData)
                  color: Theme.muted
                  opacity: root.isEnabled(row.index) ? 1 : Style.disabledOpacity
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }
              }
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
                const dropdown = root.target
                const index = row.index
                root.close()
                if (dropdown) dropdown.activated(index)
              }
            }
          }

        }

        Text {
          id: noResults
          width: parent.width
          visible: root.visibleCount === 0
          height: visible ? Style.space(28) : 0
          text: Array.isArray(root.model) && root.model.length === 0 ? "No options" : "No matches"
          color: Theme.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
        }
      }
    }
  }
}