// Blocky status bar in five sections. `center` is pinned to the exact middle of
// the bar, and centerBegin/centerEnd hang off its edges so they grow outward
// instead of shifting the clock off centre.
//
// The bar runs on whichever edge bar.json names. On a side edge it becomes a
// column, the modules drop their labels, and the five sections run top-to-bottom
// instead of left-to-right — so "left" means the start of the bar, which is the
// top when it is vertical.
import QtQuick
import Quickshell

import "."
import "Ui"
import "components"

ShellRoot {
  PanelWindow {
    id: bar

    // Edges are set from the position rather than by switching between four
    // blocks of anchors: a single anchors block can express any edge, and
    // clearing the ones that do not apply keeps Hyprland from seeing both.
    // A side bar spans top to bottom and is sized by width instead, a top or
    // bottom bar spans left to right and is sized by height.
    anchors {
      top: BarContext.vertical || BarContext.position === "top" ? true : false
      bottom: BarContext.vertical || BarContext.position === "bottom" ? true : false
      left: !BarContext.vertical || BarContext.position === "left" ? true : false
      right: !BarContext.vertical || BarContext.position === "right" ? true : false
    }

    // A side bar is as long as the screen and as wide as an icon; a top or bottom
    // bar is as wide as the screen and as tall as one row. Both dimensions are
    // stated rather than left to the anchors, because a window anchored top to
    // bottom is not given a height on its own. The screen size is taken from
    // the application rather than from an item, since the bar cannot measure
    // itself before it exists.
    readonly property var screen: Qt.application.screens && Qt.application.screens.length > 0
      ? Qt.application.screens[0]
      : null

    implicitWidth: BarContext.vertical
      ? Style.bar.sizeVertical
      : (screen ? screen.width : 1920)
    implicitHeight: BarContext.vertical
      ? (screen ? screen.height : 1080)
      : Style.bar.sizeHorizontal

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // The tooltip and panel popups anchor to this item rather than to whichever
    // button was used, because a popup resolves its anchor once, at creation. It
    // cannot anchor to the PanelWindow itself either: that is a QObject here,
    // not an item, so it has no coordinate space to place against.
    Item {
      id: barRoot
      anchors.fill: parent
    }

    Component.onCompleted: {
      TooltipHost.host = barRoot
      PanelHost.host = barRoot
    }

    Background {
      anchors.fill: parent
    }

    readonly property real gap: Style.space(2)

    // ---- start (left, or top when vertical) ----
    Section {
      anchors.top: BarContext.vertical ? parent.top : undefined
      anchors.left: BarContext.vertical ? undefined : parent.left
      anchors.horizontalCenter: BarContext.vertical ? undefined : undefined
      anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
      anchors.topMargin: BarContext.vertical ? bar.gap : undefined
      anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
      entries: BarConfig.section("left")
    }

    // ---- centre ----
    Section {
      id: centerSection
      anchors.horizontalCenter: BarContext.vertical ? undefined : parent.horizontalCenter
      anchors.verticalCenter: BarContext.vertical ? parent.verticalCenter : undefined
      entries: BarConfig.section("center")
    }

    // ---- centerBegin: grows away from the centre group ----
    Section {
      anchors.right: BarContext.vertical ? undefined : centerSection.left
      anchors.bottom: BarContext.vertical ? centerSection.top : undefined
      anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
      anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
      anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
      entries: BarConfig.section("centerBegin")
    }

    // ---- centerEnd ----
    Section {
      anchors.left: BarContext.vertical ? undefined : centerSection.right
      anchors.top: BarContext.vertical ? centerSection.bottom : undefined
      anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
      anchors.leftMargin: BarContext.vertical ? undefined : bar.gap
      anchors.topMargin: BarContext.vertical ? bar.gap : undefined
      entries: BarConfig.section("centerEnd")
    }

    // ---- end (right, or bottom when vertical) ----
    Section {
      anchors.bottom: BarContext.vertical ? parent.bottom : undefined
      anchors.right: BarContext.vertical ? undefined : parent.right
      anchors.verticalCenter: BarContext.vertical ? undefined : parent.verticalCenter
      anchors.bottomMargin: BarContext.vertical ? bar.gap : undefined
      anchors.rightMargin: BarContext.vertical ? undefined : bar.gap
      entries: BarConfig.section("right")
    }
  }
}