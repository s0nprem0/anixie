// The palette the whole shell draws with.
//
// Every palette is embedded here at build time, and the live one is picked by a
// state file the `theme` command writes. Embedding all of them rather than
// rendering just the selected one is what makes switching instant: a rebuild per
// theme is not a theme picker, and the shell is the one surface where the change
// has to be immediate — it is the thing you are looking at.
//
// The list arrives as JSON, which is a valid QML object literal, so the same file
// that the `theme` command reads in the shell feeds this one in the build.
pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
  id: root

  readonly property var palettes: (@PALETTES_JSON@)

  // The name the shell starts on, and what it falls back to if the state file is
  // missing, empty, or names something that is not in the list.
  readonly property string defaultName: "@DEFAULT_THEME@"

  property string name: defaultName

  // A palette generated from the wallpaper, handed over by the `theme` command
  // because the shell was built before the colours existed. Named `wallpaper`
  // so switching back to a curated theme simply stops using it.
  property var custom: null

  readonly property var palette: root.name === "wallpaper" && root.custom !== null
    ? root.custom
    : (palettes[name] !== undefined ? palettes[name] : palettes[defaultName])

  readonly property color bg: palette.background
  readonly property color surface: palette.surface
  readonly property color fg: palette.foreground
  readonly property color muted: palette.muted
  readonly property color primary: palette.primary
  readonly property color accent: palette.accent
  readonly property color accentAlt: palette.accentAlt
  readonly property color success: palette.success
  readonly property color danger: palette.danger

  // Translucent fill for the "glassy" bar look. Hyprland's layer blur does the
  // frosting; this only has to tint what comes through it. Derived from the
  // background rather than a separate token, so every palette gets one.
  readonly property color glass: Qt.rgba(bg.r, bg.g, bg.b, 0.95)

  // Which edge the bar sits on: top, bottom, left or right. Rendered from the Nix
  // module rather than read from bar.json, because the window is built once and
  // cannot be re-anchored afterwards — the value has to be known before the first
  // frame, and a FileView would only report it after that.
  readonly property string position: "@POSITION@"

  // Bar chrome. Modules keep the reference's shape rather than being drawn as one
  // continuous run: a fill that appears on hover and stays while a module is
  // active, no permanent outline, and a gap between neighbours. The fill strengths
  // themselves are alphas in Style.control, so they follow whichever foreground a
  // module is using.
  //
  // The corner radius for every surface — bar blocks, panels and tooltips — so the
  // whole shell shares one shape rather than each picking its own. Zero is square.
  readonly property int cornerRadius: 0
  readonly property int gap: 6

  function names() {
    return Object.keys(palettes).sort()
  }

  // The live switch, reached through the shell's IPC by the `theme` command.
  function set(next) {
    if (next === "wallpaper") {
      if (root.custom !== null) root.name = next
      return
    }

    if (palettes[next] !== undefined) root.name = next
  }

  // Ten colours from an image, in the same shape as the built-in ones.
  function setCustom(json) {
    try {
      const parsed = typeof json === "string" ? JSON.parse(json) : json
      if (parsed && typeof parsed === "object") {
        root.custom = parsed
        root.name = "wallpaper"
      }
    } catch (e) {
      console.warn("theme: the generated palette is not valid JSON")
    }
  }

  function reload() {
    let raw = ""
    try {
      raw = themeFile.text()
    } catch (e) {
      raw = ""
    }

    const wanted = String(raw).trim()
    if (wanted !== "" && palettes[wanted] !== undefined) root.name = wanted
  }

  // Read once at startup for the saved choice, and not watched.
  //
  // `watchChanges` was tried first and never fired on this Quickshell: the file
  // read correctly at load and no later write was ever noticed — not a truncated
  // rewrite, not a replace, not a touch. Rather than leave a watch that does
  // nothing, the live path goes through the shell's IPC, the same way the dock and
  // the panels are driven. This is only here so a shell that restarts comes back
  // on the saved theme rather than the built-in default.
  property FileView themeFile: FileView {
    path: Qt.resolvedUrl("@THEME_STATE@")
    printErrors: false
    blockLoading: true

    Component.onCompleted: root.reload()
  }
}
