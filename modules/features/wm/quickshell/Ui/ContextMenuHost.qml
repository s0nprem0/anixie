pragma Singleton

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

// A small action menu, opened by a right click.
//
// Distinct from the tray's QsMenuAnchor: that one renders a menu another
// application supplies over DBusMenu. This is the shell's own menu — bar
// widgets and the desktop put a list of { label, glyph, enabled, danger,
// separator, action } objects in and get a keyboard- and mouse-driven popup
// back, with a curtain that closes it on the next click anywhere else.
QtObject {
  id: root

  property var items: []
  property var target: null
  property rect anchorRect: Qt.rect(0, 0, 0, 0)
  property bool opened: false
  property bool closing: false
  property real reveal: 0
  property int index: -1

  // Monotonic id for the currently open session, used to ignore stale
  // callbacks (focus restore, choose) after a newer menu has opened.
  property int openGeneration: 0

  // How the popup is placed against the anchor rect. A bar widget uses the
  // bar's own edge; a desktop click grows down and right from the pointer.
  property int edges: Edges.Bottom
  property int gravity: Edges.Bottom

  readonly property int rowHeight: Math.max(24, Style.font.body + Style.space(10))
  readonly property int separatorHeight: Style.space(9)
  readonly property int menuWidth: Style.space(230)
  readonly property int padding: Style.space(4)

  readonly property int menuHeight: {
    let height = root.padding * 2
    for (let i = 0; i < root.items.length; i++) {
      const item = root.items[i]
      height += item && item.separator === true ? root.separatorHeight : root.rowHeight
    }
    return height
  }

  readonly property int maxMenuHeight: {
    let limit = 420
    if (root.target) {
      try {
        const screen = Screens.byName(Screens.nameOf(root.target))
        if (screen && screen.height) limit = Math.max(160, screen.height - 80)
      } catch (e) {
      }
    }
    return limit
  }

  // Away from the bar, the same direction a tooltip takes: below a top bar,
  // above a bottom one, beside a side bar.
  function barEdge() {
    return BarContext.position === "bottom"
      ? Edges.Top
      : BarContext.position === "left"
        ? Edges.Right
        : BarContext.position === "right"
          ? Edges.Left
          : Edges.Bottom
  }

  // Anchored to a bar widget, which is what a right click on the bar does.
  function open(entries, item) {
    if (!entries || entries.length === 0 || !item) return

    root.edges = root.barEdge()
    root.gravity = root.barEdge()
    root.anchorRect = Qt.rect(0, 0, Math.round(item.width), Math.round(item.height))
    root.target = item
    root.show(entries)
  }

  // Anchored to a point inside an item, which is what a right click on the
  // desktop does. Default popup placement: top-left of the rect, growing down
  // and right.
  function openAt(entries, item, x, y) {
    if (!entries || entries.length === 0 || !item) return

    root.edges = Edges.Top | Edges.Left
    root.gravity = Edges.Bottom | Edges.Right
    root.anchorRect = Qt.rect(Math.round(x), Math.round(y), 0, 0)
    root.target = item
    root.show(entries)
  }

  // Drop leading, trailing, and repeated separators so the menu never shows an
  // empty divider row.
  function normalize(entries) {
    if (!entries) return []
    const out = []
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (!entry) continue
      if (entry.separator === true) {
        if (out.length === 0) continue
        if (out[out.length - 1].separator === true) continue
        out.push(entry)
      } else {
        out.push(entry)
      }
    }
    if (out.length > 0 && out[out.length - 1].separator === true) out.pop()
    return out
  }

  function show(entries) {
    root.items = root.normalize(entries)
    root.index = root.firstEnabled()
    root.openGeneration += 1
    root.closing = false
    root.opened = true
    root.reveal = 1
    menuFlickable.contentY = 0
  }

  onItemsChanged: {
    if (root.index < 0 || root.index >= root.items.length || !root.actionable(root.items[root.index])) {
      root.index = root.firstEnabled()
    }
  }

  function targetAlive() {
    if (!root.target) return false
    try {
      const value = root.target.width
      return true
    } catch (e) {
      return false
    }
  }

  function close() {
    if (!root.opened && !root.closing) return
    root.opened = false
    root.closing = true
    root.reveal = 0
    Qt.callLater(function () {
      // Keep the window mapped for the close animation, then clear.
      closeTimer.restart()
    })
  }

  property Timer closeTimer: Timer {
    interval: 160
    repeat: false
    onTriggered: {
      root.closing = false
      root.target = null
      root.items = []
      root.index = -1
    }
  }

  // Close the menu if its anchor disappears (panel closed, bar reloaded, ...).
  property Timer livenessTimer: Timer {
    interval: 100
    repeat: true
    running: root.opened
    onTriggered: {
      if (!root.targetAlive()) root.close()
    }
  }

  function actionable(item) {
    return !!item && item.separator !== true && item.enabled !== false
  }

  function firstEnabled() {
    for (let i = 0; i < root.items.length; i++) {
      if (root.actionable(root.items[i])) return i
    }
    return -1
  }

  // Wrap through the actionable rows, skipping separators and disabled ones.
  function move(delta) {
    if (root.items.length === 0) return

    let i = root.index
    for (let step = 0; step < root.items.length; step++) {
      i = (i + delta + root.items.length) % root.items.length
      if (root.actionable(root.items[i])) {
        root.index = i
        return
      }
    }
  }

  function choose(index) {
    const item = root.items[index]
    if (!root.actionable(item)) return

    const gen = root.openGeneration
    root.close()
    if (gen !== root.openGeneration) return
    if (typeof item.action === "function") item.action()
  }

  function activate() {
    root.choose(root.index)
  }

  // The click-catcher. A menu is transient: the next click anywhere closes it
  // without reaching whatever was underneath, which is what a menu does
  // everywhere else.
  property Curtain curtain: Curtain {
    screens: root.opened && root.target !== null && root.targetAlive() ? [root.target] : []
    resolveScreen: true
    wlrLayer: WlrLayer.Top
    namespace: "quickshell-context-curtain"
    keyboardFocus: WlrKeyboardFocus.None
    onPressed: function (screenName) { root.close() }
  }

  property PopupWindow window: PopupWindow {
    id: popupWindow
    visible: (root.opened || root.closing) && root.target !== null && root.targetAlive()
    onVisibleChanged: {
      if (!visible) return
      const gen = root.openGeneration
      Qt.callLater(function () {
        if (gen !== root.openGeneration) return
        keys.forceActiveFocus()
      })
    }
    color: "transparent"

    anchor.item: root.target
    anchor.rect: root.anchorRect
    anchor.edges: root.edges
    anchor.gravity: root.gravity
    anchor.adjustment: PopupAdjustment.ResizeY | PopupAdjustment.SlideX

    implicitWidth: root.menuWidth
    implicitHeight: Math.min(root.menuHeight, root.maxMenuHeight)

    // Keep mapped while the close animation runs.
    opacity: root.reveal
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-context"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    HyprlandFocusGrab {
      active: root.opened || root.closing
      windows: [popupWindow]
      onCleared: root.close()
    }

    RectangularShadow {
      anchors.fill: cardShadowTarget
      radius: Theme.cornerRadius
      blur: 16
      spread: -2
      offset.y: 4
      color: Qt.rgba(0, 0, 0, 0.35)
    }

    PopupCard {
      id: cardShadowTarget
      anchors.fill: parent
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Component.onCompleted: keys.forceActiveFocus()

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.move(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.move(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          root.index = root.firstEnabled()
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          for (let i = root.items.length - 1; i >= 0; i--) {
            if (root.actionable(root.items[i])) { root.index = i; break }
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.move(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          root.activate()
          event.accepted = true
        }
      }
    }

    Flickable {
      id: menuFlickable
      anchors.fill: parent
      anchors.margins: 0
      contentWidth: width
      contentHeight: menuColumn.implicitHeight + root.padding * 2
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar {}

      Column {
        id: menuColumn
        width: parent.width - root.padding * 2
        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        spacing: 0

        Repeater {
          model: root.items

          delegate: Item {
            required property var modelData
            required property int index

            width: parent.width
            height: modelData && modelData.separator === true ? root.separatorHeight : root.rowHeight

            Rectangle {
              visible: modelData && modelData.separator === true
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 1
              color: Theme.muted
              opacity: 0.4
            }

            ContextMenuRow {
              visible: !(modelData && modelData.separator === true)
              anchors.fill: parent
              label: modelData && modelData.label ? modelData.label : ""
              glyph: modelData && modelData.glyph ? modelData.glyph : ""
              iconName: modelData && modelData.iconName ? modelData.iconName : ""
              trailingIcon: modelData && modelData.trailingIcon ? modelData.trailingIcon : ""
              activeIcon: modelData && modelData.activeIcon ? modelData.activeIcon : ""
              activeText: modelData && modelData.activeText ? modelData.activeText : ""
              danger: modelData && modelData.danger === true
              available: !modelData || modelData.enabled !== false
              selected: root.index === index
              onClicked: root.choose(index)
            }
          }
        }
      }
    }
  }
}
