import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import ".."
import "../components"

// Minimal workspace overview: lists workspaces and their windows.
// Slice 1: no previews, just names and titles.
Item {
  id: root

  readonly property var workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []

  property string previewPath: ""
  property bool previewVisible: false

  // Best-effort transactional move state. Hyprland does not report success, so
  // we retry once if the window is still on its source workspace.
  property var pendingMove: null

  property Timer moveRetryTimer: Timer {
    interval: 600
    repeat: false
    onTriggered: {
      const pm = root.pendingMove
      if (!pm) return
      let stillThere = false
      const clients = HyprlandAdapter.clients || []
      for (let i = 0; i < clients.length; i++) {
        if (clients[i].address === pm.address && clients[i].workspace === pm.from) {
          stillThere = true
          break
        }
      }
      if (stillThere) {
        Commands.run("hyprctl dispatch movetoworkspace " + pm.to + ",address:" + pm.address)
      }
      root.pendingMove = null
    }
  }

  property Process captureProc: Process {
    running: false
    stdout: StdioCollector { }
    onExited: function (code) {
      if (code === 0) root.previewVisible = true
    }
  }

  function captureWindow(win) {
    if (!win || !win.at || !win.size) return
    const x = win.at[0]
    const y = win.at[1]
    const w = win.size[0]
    const h = win.size[1]
    if (w <= 0 || h <= 0) return
    root.previewPath = "/tmp/quickshell-ws-preview.png"
    root.previewVisible = false
    root.captureProc.command = ["grim", "-g", x + "," + y + " " + w + "x" + h, root.previewPath]
    root.captureProc.running = false
    root.captureProc.running = true
  }

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

              delegate: Row {
                required property var modelData
                property string address: String(modelData.address || "")
                spacing: Style.space(6)

                Drag.active: dragArea.drag.active
                Drag.source: parent
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                Image {
                  width: Style.space(16)
                  height: Style.space(16)
                  source: Quickshell.iconPath(String(modelData.class || ""), "")
                  visible: source !== ""
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  text: "• " + String(modelData.title || modelData.class || "window")
                  color: Theme.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.address) Commands.run("hyprctl dispatch 'hl.dsp.focus({window = \"" + modelData.address + "\"})'")
                  }
                }

                MouseArea {
                  id: dragArea
                  anchors.fill: parent
                  drag.target: parent
                  onPressed: parent.Drag.active = true
                  onReleased: parent.Drag.active = false
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: Commands.run("hyprctl dispatch 'hl.dsp.focus({workspace = " + modelData.id + "})'")
            }

            DropArea {
              anchors.fill: parent
              onDropped: function (drop) {
                const source = drop.source
                const addr = source && source.address ? source.address : ""
                if (addr === "") return

                // Record the source workspace for a best-effort retry.
                let from = -1
                const clients = HyprlandAdapter.clients || []
                for (let i = 0; i < clients.length; i++) {
                  if (clients[i].address === addr) { from = clients[i].workspace; break }
                }
                root.pendingMove = { address: addr, from: from, to: modelData.id }
                root.moveRetryTimer.restart()

                Commands.run("hyprctl dispatch movetoworkspace " + modelData.id + ",address:" + addr)
              }
            }
          }
        }
      }
    }

    Image {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: Style.space(20)
      width: Style.space(320)
      height: Style.space(180)
      visible: root.previewVisible && root.previewPath !== ""
      source: root.previewPath !== "" ? "file://" + root.previewPath : ""
      fillMode: Image.PreserveAspectFit
      cache: false
      smooth: true
    }
  }
}
