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
    if (!root.available) return
    if (list.opened) list.close()
    else list.open()
  }

  function keyStep(direction) {
    if (!root.available || root.model.length === 0) return false

    const from = root.currentIndex < 0 ? 0 : root.currentIndex
    const next = Math.max(0, Math.min(root.model.length - 1, from + direction))
    if (next !== root.currentIndex) root.activated(next)

    // The key stays here whether or not it moved anything: at the end of the
    // list there is nowhere to go, and handing it back to the panel would walk
    // the focus off the thing being chosen.
    return true
  }

  readonly property var currentEntry: {
    if (root.model.length === 0 || root.currentIndex < 0) return null
    const entry = root.model[Math.min(root.currentIndex, root.model.length - 1)]
    return typeof entry === "string" ? { label: entry, value: entry } : entry
  }

  readonly property string currentLabel: root.currentEntry ? String(root.currentEntry.label) : root.placeholder

  function labelFor(entry) {
    return typeof entry === "string" ? entry : String(entry && entry.label !== undefined ? entry.label : "")
  }

  implicitWidth: Style.space(160)
  implicitHeight: Style.space(26)
  height: implicitHeight
  opacity: root.available ? 1 : Style.disabledOpacity

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
    y: root.height + Style.space(4)
    width: root.width
    implicitHeight: Math.min(listContent.implicitHeight, Style.space(260))
    padding: 0
    modal: false
    focus: true

    property bool flipped: false

    function updatePosition() {
      const spacing = Style.space(4)
      const maxH = Style.space(260)
      const popupH = Math.min(listContent.implicitHeight, maxH)
      let pos = root.height + spacing
      let flip = false

      try {
        const rootPos = root.mapToItem(null, 0, root.height)
        const screenH = (root.Window && root.Window.window ? root.Window.window.height : 0)
        if (screenH > 0 && rootPos.y + popupH > screenH - spacing) {
          if (popupH < root.height + rootPos.y - spacing) {
            pos = -(popupH + spacing)
            flip = true
          }
        }
      } catch (e) {
      }

      list.y = pos
      list.flipped = flip
    }

    onAboutToShow: updatePosition()
    Connections {
      target: listContent
      function onImplicitHeightChanged() { if (list.opened) list.updatePosition() }
    }

    // Which row the keyboard is on while the popup is up. Kept separate from
    // `root.currentIndex`: that one belongs to the caller's binding, and
    // writing it from here would replace the binding and stop the control
    // following the value it is meant to show.
    property int highlighted: -1

    function moveHighlight(delta) {
      if (root.model.length === 0) return
      const from = list.highlighted < 0 ? (delta > 0 ? -1 : 0) : list.highlighted
      const next = Math.max(0, Math.min(root.model.length - 1, from + delta))
      list.highlighted = next
      listContent.positionViewAtIndex(next, ListView.Contain)
    }

    function choose() {
      // Close before reporting the choice: the caller may rebuild the model
      // this dropdown is part of (a module moving sections, a screen change),
      // which would destroy the popup and leave `list` undefined below.
      const chosen = list.highlighted
      list.close()
      if (chosen >= 0 && chosen < root.model.length) {
        root.activated(chosen)
      }
    }

    // The list can be longer than the popup — nineteen modes on one monitor —
    // and a ListView starts at the top. Opening at the current entry is what
    // makes the control say what is selected without a scroll first.
    onOpened: {
      list.highlighted = root.model.length === 0
        ? -1
        : (root.currentIndex >= 0 ? root.currentIndex : 0)
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

    contentItem: ListView {
      id: listContent
      clip: true
      implicitHeight: contentHeight
      model: root.model
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
        height: Style.space(26)
        required property int index
        required property var modelData

        readonly property bool selected: row.index === list.highlighted

        color: rowMouse.containsMouse
          ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.selectedFillAlpha)
          : (row.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Style.control.hoverFillAlpha) : "transparent")

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: root.labelFor(row.modelData)
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
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