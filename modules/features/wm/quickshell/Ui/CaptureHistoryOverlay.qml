import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"

PanelWindow {
  id: root
  screen: Screens.focused

  anchors.top: true
  anchors.bottom: true
  anchors.left: true
  anchors.right: true
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  visible: CaptureHistory.shown

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "quickshell-capture-history"
  WlrLayershell.keyboardFocus: CaptureHistory.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  MouseArea {
    anchors.fill: parent
    onClicked: CaptureHistory.hide()
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.background
    opacity: 0.6
  }

  Rectangle {
    id: panel
    width: Math.min(parent.width * 0.8, Style.space(900))
    height: Math.min(parent.height * 0.7, Style.space(560))
    anchors.centerIn: parent
    radius: Theme.cornerRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Style.strokeWidth

    // Swallows clicks on the panel's own empty space, which would otherwise fall
    // through to the dismiss area behind it and close the shelf.
    MouseArea {
      anchors.fill: parent
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "Recent Captures"
          color: Theme.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }

        Item { width: parent.width - 200; height: 1 }

        WidgetButton {
          text: "Refresh"
          onPressed: CaptureHistory.refresh()
        }
        WidgetButton {
          text: "Close"
          onPressed: CaptureHistory.hide()
        }
      }

      Flickable {
        width: parent.width
        height: parent.height - Style.space(48)
        contentWidth: grid.width
        contentHeight: grid.height
        clip: true

        Grid {
          id: grid
          columns: 4
          spacing: Style.space(12)

          Repeater {
            model: CaptureHistory.items
            delegate: Rectangle {
              id: card
              width: (panel.width - Style.space(32) - grid.spacing * 3) / 4
              height: width * 0.7 + Style.space(44)
              radius: Theme.cornerRadius
              color: Theme.background
              border.color: cardHover.hovered ? Theme.primary : Theme.border
              border.width: Style.strokeWidth

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Image {
                  width: parent.width
                  height: parent.height - Style.space(38)
                  source: "file://" + modelData
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                }

                Text {
                  width: parent.width
                  text: modelData.split("/").pop()
                  color: Theme.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: CaptureHistory.reveal(modelData)
              }

              // On the card rather than the MouseArea: the action buttons take
              // the hover from a MouseArea beneath them, which hid the row the
              // moment the pointer reached it.
              HoverHandler {
                id: cardHover
              }

              Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Style.space(6)
                spacing: Style.space(2)
                visible: cardHover.hovered

                WidgetButton {
                  text: "Edit"
                  onPressed: CaptureHistory.editPath(modelData)
                }
                WidgetButton {
                  text: "Folder"
                  onPressed: CaptureHistory.openFolder(modelData)
                }
                WidgetButton {
                  text: "Copy"
                  onPressed: CaptureHistory.copyPath(modelData)
                }
                WidgetButton {
                  text: "URI"
                  onPressed: CaptureHistory.copyUri(modelData)
                }
                WidgetButton {
                  text: "Share"
                  onPressed: {
                    Quickshell.execDetached(["sh", "-c", "echo \"$1\" > ${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie/last-capture && capture-share", "sh", modelData])
                    CaptureHistory.hide()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
