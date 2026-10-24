pragma Singleton

import QtQuick
import Quickshell
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
  property int index: -1

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

  function show(entries) {
    root.items = entries
    root.index = root.firstEnabled()
    root.opened = true
  }

  function close() {
    root.opened = false
    root.target = null
    root.items = []
    root.index = -1
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

    root.close()
    if (typeof item.action === "function") item.action()
  }

  function activate() {
    root.choose(root.index)
  }

  // The click-catcher. A menu is transient: the next click anywhere closes it
  // without reaching whatever was underneath, which is what a menu does
  // everywhere else.
  property Item curtain: Item {
    visible: false

    Variants {
      model: root.opened && root.target !== null ? [root.target] : []

      delegate: PanelWindow {
        required property var modelData

        screen: Screens.byName(Screens.nameOf(modelData))
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-context-curtain"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onPressed: root.close()
        }
      }
    }
  }

  property PopupWindow window: PopupWindow {
    visible: root.opened && root.target !== null
    color: "transparent"

    anchor.item: root.target
    anchor.rect: root.anchorRect
    anchor.edges: root.edges
    anchor.gravity: root.gravity

    implicitWidth: root.menuWidth
    implicitHeight: root.menuHeight

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-context"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Theme.surface
      border.color: Theme.border
      border.width: Style.strokeWidth
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
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activate()
          event.accepted = true
        }
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: root.padding

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
