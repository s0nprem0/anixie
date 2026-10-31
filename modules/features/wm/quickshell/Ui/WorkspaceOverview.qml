import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."
import "../components"

// Minimal workspace overview: lists workspaces and their windows.
// Slice 1: no previews, just names and titles.
Item {
  id: root

  readonly property var workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)

    Column {
      anchors.centerIn: parent
      spacing: Style.space(12)
      width: Math.min(parent.width - Style.space(40), Style.space(600))

      Repeater {
        model: root.workspaces

        delegate: Rectangle {
          required property var modelData
          width: parent.width
          height: content.implicitHeight + Style.space(12)
          radius: Theme.cornerRadius
          color: Theme.surface
          border.color: Theme.border
          border.width: Style.strokeWidth

          Column {
            id: content
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(4)

            Text {
              text: "Workspace " + modelData.id
              color: Theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              renderType: Text.NativeRendering
            }

            Repeater {
              model: modelData.toplevels ? modelData.toplevels.values : []

              delegate: Text {
                required property var modelData
                text: "• " + String(modelData.title || modelData.class || "window")
                color: Theme.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }
            }
          }
        }
      }
    }
  }
}
