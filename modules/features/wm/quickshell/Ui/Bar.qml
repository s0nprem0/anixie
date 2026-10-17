pragma Singleton

import QtQuick
import ".."

// The handle a custom `type: "qml"` module gets handed as its `bar` property.
// It is a thin front over the singletons the bar already runs on, so a module
// dropped into ~/.config/quickshell/modules/ can be written against a stable
// contract instead of reaching into Style, Theme, BarContext and the rest by
// import path.
//
// Omarchy's bar exposes the same shape, so a module ported from there needs
// only `bar.foreground` rather than a fresh import for every singleton.
QtObject {
  id: root

  // Theme colours, live-updated because they bind to the Theme singleton.
  readonly property color foreground: Theme.fg
  readonly property color background: Theme.bg
  readonly property color urgent: Theme.danger
  readonly property color surface: Theme.surface
  readonly property color muted: Theme.muted
  readonly property color accent: Theme.accent

  readonly property string fontFamily: Style.font.family

  readonly property string position: BarContext.position
  readonly property bool vertical: BarContext.vertical
  readonly property int barSize: BarContext.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  readonly property int iconSize: Style.bar.iconSize
  readonly property int iconSlot: Style.bar.iconSlot
  readonly property int iconCanvas: Style.bar.iconCanvas

  function run(command) {
    Commands.run(command)
  }

  function runQuoted(binary, args) {
    Commands.runQuoted(binary, args)
  }

  function showTooltip(target, text) {
    TooltipHost.show(text, target)
  }

  function hideTooltip(target) {
    TooltipHost.hide(target)
  }

  function togglePanel(anchor, builder) {
    PanelHost.toggle(anchor, builder)
  }

  function showPanel(anchor, builder) {
    PanelHost.show(anchor, builder)
  }

  function closePanel() {
    PanelHost.close()
  }
}