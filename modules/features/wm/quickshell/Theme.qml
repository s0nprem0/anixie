// Blocky palette. This file is a template: the theme module renders it, so
// the copy Quickshell loads already carries the colours from
// modules/features/theming/colors.nix instead of a hardcoded copy of them.
pragma Singleton

import QtQuick

QtObject {
  readonly property color bg: "@BG@"
  readonly property color surface: "@SURFACE@"
  readonly property color fg: "@FG@"
  readonly property color muted: "@MUTED@"
  readonly property color primary: "@PRIMARY@"
  readonly property color accent: "@ACCENT@"
  readonly property color success: "@SUCCESS@"
  readonly property color danger: "@DANGER@"

  // Translucent fill for the "glassy" bar look. Hyprland's layer blur does the
  // frosting; this only has to tint what comes through it.
  readonly property color glass: "@BG_ALPHA_F2@"

  // Which edge the bar sits on: top, bottom, left or right. Rendered from the
  // Nix module rather than read from bar.json, because the window is built once
  // and cannot be re-anchored afterwards — the value has to be known before the
  // first frame, and a FileView would only report it after that.
  readonly property string position: "@POSITION@"

  // Bar chrome. Modules keep the reference's shape rather than being drawn as
  // one continuous run: a fill that appears on hover and stays while a module
  // is active, no permanent outline, and a gap between neighbours. The fill
  // strengths themselves are alphas in Style.control, so they follow whichever
  // foreground a module is using.
  //
  // The corner radius for every surface — bar blocks, panels and tooltips —
  // so the whole shell shares one shape rather than each picking its own.
  // Zero is square.
  readonly property int cornerRadius: 0
  readonly property int gap: 6
}