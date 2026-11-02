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
  // barSize represents the full bar dimension (horizontal height or vertical width)
  readonly property int barSize: BarContext.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  readonly property int iconSize: Style.bar.iconSize
  readonly property int iconSlot: Style.bar.iconSlot
  readonly property int iconCanvas: Style.bar.iconCanvas

  // A trusted shell-command interface. Arbitrary module-provided command strings
  // are not sanitized for safety - callers must treat them as trusted.
  function run(command) {
    if (command === undefined || command === null) return
    try {
      Commands.run(command)
    } catch (e) {
    }
  }

  // A binary and its arguments, each quoted individually via Util.shellQuote.
  // Argument boundaries are preserved; dynamic arguments are quoted safely.
  function runQuoted(binary, args) {
    if (binary === undefined || binary === null) return
    try {
      Commands.runQuoted(binary, args)
    } catch (e) {
    }
  }

  function showTooltip(target, text) {
    if (!target || text === undefined || text === null) return
    try {
      TooltipHost.show(String(text), target)
    } catch (e) {
    }
  }

  function hideTooltip(target) {
    if (!target) return
    try {
      TooltipHost.hide(target)
    } catch (e) {
    }
  }

  function togglePanel(anchor, builder) {
    if (!anchor || !builder) return
    try {
      PanelHost.toggle(anchor, builder)
    } catch (e) {
    }
  }

  function showPanel(anchor, builder) {
    if (!anchor || !builder) return
    try {
      PanelHost.show(anchor, builder)
    } catch (e) {
    }
  }

  function closePanel() {
    try {
      PanelHost.close()
    } catch (e) {
    }
  }
}
