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

  signal activated(int index)

  readonly property var currentEntry: {
    if (root.model.length === 0) return null
    const entry = root.model[Math.max(0, Math.min(root.model.length - 1, root.currentIndex))]
    return typeof entry === "string" ? { label: entry, value: entry } : entry
  }

  readonly property string currentLabel: root.currentEntry ? String(root.currentEntry.label) : root.placeholder

  function labelFor(entry) {
    return typeof entry === "string" ? entry : String(entry && entry.label !== undefined ? entry.label : "")
  }

  implicitWidth: Style.space(160)
  implicitHeight: Style.space(26)
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: mouse.containsMouse
      ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha)
      : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Style.control.hoverFillAlpha * 0.5)
    border.color: list.opened || mouse.containsMouse ? Theme.primary : Theme.muted
    border.width: 1
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
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
    color: mouse.containsMouse ? Theme.primary : Theme.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
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

    background: Rectangle {
      color: Theme.surface
      radius: Theme.cornerRadius
      border.color: Theme.muted
      border.width: 1
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
      currentIndex: root.currentIndex
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: row
        width: ListView.view.width
        height: Style.space(26)
        required property int index
        required property var modelData

        readonly property bool selected: row.index === root.currentIndex

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
            root.activated(row.index)
            list.close()
          }
        }
      }
    }
  }
}