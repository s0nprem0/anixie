import QtQuick
import ".."
import Quickshell
import Quickshell.Io

// Workspace pills, driven by hyprctl JSON rather than the Hyprland plugin so
// no plugin API has to be assumed. Only the 1-5 the keybinds reach are shown.
Item {
  id: root
  implicitHeight: 22

  property var workspaces: []
  property int active: -1

  Process {
    id: probe
    running: true
    command: ["hyprctl", "-j", "workspaces"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const all = JSON.parse(this.text)
          const kept = []
          for (let i = 0; i < all.length; i++) {
            if (all[i].windows > 0 || all[i].id <= 5)
              kept.push({ id: all[i].id, name: all[i].name })
          }
          root.workspaces = kept
        } catch (e) {
          root.workspaces = []
        }
      }
    }
  }

  Process {
    id: activeProbe
    running: true
    command: ["hyprctl", "-j", "activeworkspace"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.active = JSON.parse(this.text).id
        } catch (e) {
          root.active = -1
        }
      }
    }
  }

  Timer {
    running: true
    interval: 2000
    triggeredOnStart: true
    onTriggered: {
      probe.running = false; probe.running = true
      activeProbe.running = false; activeProbe.running = true
    }
  }

  Row {
    anchors.fill: parent
    spacing: Theme.gap

    Repeater {
      model: root.workspaces
      delegate: Rectangle {
        required property var modelData
        readonly property bool isActive: modelData.id === root.active

        width: isActive ? 26 : 18
        height: 22
        radius: Theme.blockRadius
        color: isActive ? Theme.primary : Theme.surface

        Text {
          anchors.centerIn: parent
          text: parent.modelData.name
          color: parent.isActive ? Theme.bg : Theme.muted
          font.family: "JetBrains Mono"
          font.pixelSize: 12
          font.weight: parent.isActive ? Font.DemiBold : Font.Normal
        }
      }
    }
  }
}
