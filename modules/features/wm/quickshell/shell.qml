// Flat status bar, modelled on the reference design: a 26px transparent strip
// with no background blocks, laid out in five sections so `center` stays
// pinned to the exact middle while centerBegin/centerEnd grow outward.
import QtQuick
import Quickshell

import "."
import "Ui"
import "components"

ShellRoot {
  PanelWindow {
    id: bar
    anchors {
      top: true
      left: true
      right: true
    }
    implicitHeight: Style.bar.sizeHorizontal
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // The tooltip popup anchors to this item rather than to whichever button is
    // hovered, because a popup resolves its anchor once, at creation. It cannot
    // anchor to the PanelWindow itself either: that is a QObject here, not an
    // item, so it has no coordinate space to place against.
    Item {
      id: barRoot
      anchors.fill: parent
    }

    Component.onCompleted: TooltipHost.host = barRoot

    Background {
      anchors.fill: parent
      implicitHeight: Style.bar.sizeHorizontal
    }

    // ---- left ----
    Section {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      entries: BarConfig.section("left")
    }

    // ---- center ----
    Section {
      id: centerSection
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      entries: BarConfig.section("center")
    }

    // ---- centerBegin: grows leftwards off the center group ----
    Section {
      anchors.right: centerSection.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      entries: BarConfig.section("centerBegin")
    }

    // ---- centerEnd: grows rightwards off the center group ----
    Section {
      anchors.left: centerSection.right
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      entries: BarConfig.section("centerEnd")
    }

    // ---- right ----
    Section {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      entries: BarConfig.section("right")
    }
  }
}