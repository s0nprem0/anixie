// Blocky status bar in five sections: `center` is pinned to the exact middle
// of the bar, and centerBegin/centerEnd hang off its edges so they grow
// outward instead of shifting the clock off centre.
import QtQuick
import Quickshell

import "."
import "components"

ShellRoot {
  PanelWindow {
    id: bar

    anchors {
      top: true
      left: true
      right: true
    }
    implicitHeight: Theme.barHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    Background {}

    // ---- left ----
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Theme.barPad
      width: leftSection.implicitWidth + Theme.blockPad * 2
      visible: leftSection.implicitWidth > 0
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Section {
        id: leftSection
        anchors.centerIn: parent
        entries: BarConfig.section("left")
      }
    }

    // ---- center ----
    Rectangle {
      id: centerBlock
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: centerSection.implicitWidth + Theme.blockPad * 2
      visible: centerSection.implicitWidth > 0
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Section {
        id: centerSection
        anchors.centerIn: parent
        entries: BarConfig.section("center")
      }
    }

    // ---- centerBegin: grows leftwards off the center block ----
    Rectangle {
      anchors.right: centerBlock.left
      anchors.rightMargin: Theme.gap
      anchors.verticalCenter: parent.verticalCenter
      width: beginSection.implicitWidth + Theme.blockPad * 2
      visible: beginSection.implicitWidth > 0
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Section {
        id: beginSection
        anchors.centerIn: parent
        entries: BarConfig.section("centerBegin")
      }
    }

    // ---- centerEnd: grows rightwards off the center block ----
    Rectangle {
      anchors.left: centerBlock.right
      anchors.leftMargin: Theme.gap
      anchors.verticalCenter: parent.verticalCenter
      width: endSection.implicitWidth + Theme.blockPad * 2
      visible: endSection.implicitWidth > 0
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Section {
        id: endSection
        anchors.centerIn: parent
        entries: BarConfig.section("centerEnd")
      }
    }

    // ---- right ----
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Theme.barPad
      width: rightSection.implicitWidth + Theme.blockPad * 2
      visible: rightSection.implicitWidth > 0
      radius: Theme.blockRadius
      color: Theme.bg
      border.color: Theme.surface
      border.width: 1

      Section {
        id: rightSection
        anchors.centerIn: parent
        entries: BarConfig.section("right")
      }
    }
  }
}