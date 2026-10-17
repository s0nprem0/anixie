// Blocky status bar. Replaces waybar: every module sits in its own rounded
// slab, which is what makes it read as "blocky" rather than one flat strip.
import QtQuick
import Quickshell

import "."
import "components"

ShellRoot {
  PanelWindow {
    id: bar
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // ---- left: workspaces ----
    Rectangle {
      id: wsBlock
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.leftMargin: Theme.barPad
      anchors.topMargin: 6
      anchors.bottomMargin: 6
      width: wsRow.implicitWidth + Theme.blockPad * 2
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Workspaces {
        id: wsRow
        anchors.centerIn: parent
      }
    }

    // ---- centre: clock ----
    Rectangle {
      id: clockBlock
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: 6
      anchors.bottomMargin: 6
      width: clock.implicitWidth + Theme.blockPad * 2
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Clock {
        id: clock
        anchors.centerIn: parent
      }
    }

    // ---- right: wifi, volume, battery ----
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: Theme.barPad
      anchors.topMargin: 6
      anchors.bottomMargin: 6
      width: statusRow.implicitWidth + Theme.blockPad * 2
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: Theme.gap * 2

        Wifi {}
        Volume {}
        Battery {}
      }
    }
  }
}
