pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Bar geometry and the spacing step. The numbers come from the reference
// design the bar is modelled on: a 26px horizontal bar whose icons are fitted
// to 12px of painted glyph rather than trusting the font's point size.
QtObject {
  id: style

  // The global text size, as a multiplier over the sizes below. The `textsize`
  // command owns the value: it writes a state file the shell reads once at
  // startup (for a restart) and pushes changes through the shell's IPC (for a
  // running one). Bar geometry itself does not scale — only what is read.
  property real textScale: 1.0

  readonly property QtObject font: QtObject {
    readonly property string family: "JetBrainsMono Nerd Font"
    readonly property int caption: Math.round(10 * style.textScale)
    readonly property int bodySmall: Math.round(11 * style.textScale)
    readonly property int body: Math.round(12 * style.textScale)
    readonly property int subtitle: Math.round(13 * style.textScale)
  }

  readonly property string fontFamily: font.family

  function setTextScale(scale) {
    const n = Number(scale)
    if (isFinite(n) && n > 0) style.textScale = n
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/anixie/theme"

  // Read once, not watched: the live path is the IPC call, which is the same
  // arrangement the theme uses and for the same reason — a FileView watch on
  // these files never fired on this Quickshell.
  property FileView textSizeFile: FileView {
    path: Qt.resolvedUrl(style.stateDir + "/textscale")
    printErrors: false
    blockLoading: true
    Component.onCompleted: {
      try {
        style.setTextScale(Number(String(style.textSizeFile.text()).trim()) / 100)
      } catch (e) {
      }
    }
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: 26
    readonly property int sizeVertical: 28

    // Extent of an icon button, and the square its glyph is laid out in.
    readonly property int iconSlot: 27
    readonly property int iconCanvas: 16

    // Font size the glyph is measured at before being scaled to iconSize.
    readonly property int iconFont: 13

    // The painted target every glyph is fitted to, whichever way it is drawn.
    readonly property int iconSize: 12

    // Slot for a compact status readout with no glyph of its own.
    readonly property int statusSlot: 21
  }

  // Fill strengths for the bar's control chrome, as alphas over whatever
  // foreground a module is using. Idle controls paint nothing at all: hover and
  // the active state are what make a module read as a block, which is how the
  // reference does it rather than outlining every module permanently.
  readonly property QtObject control: QtObject {
    readonly property real hoverFillAlpha: 0.08
    readonly property real selectedFillAlpha: 0.18
    readonly property real pressedFillAlpha: 0.22
  }

  // Spacing scale. `space` rounds so callers can pass loose pixel values and
  // land on whole pixels; `spaceReal` keeps fractional geometry such as the
  // half-pixel offsets that centre odd-width slots.
  function spaceReal(px) {
    const n = Number(px)
    if (!isFinite(n) || n <= 0) return 0
    return n
  }

  // The steps a gap is allowed to land on. Small values snap to the nearest one,
  // so a padding cannot be 14 here and 16 there for no reason — which is what it
  // was: `space` used to round and nothing else, and seventeen distinct values
  // between 2 and 48 came out of it.
  readonly property var steps: [0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48]

  // A value above the last step is a *size* — a panel width, a list cap — not a
  // gap, and passes through untouched. The two uses share this function because
  // they always have; separating them would mean touching every call site to
  // change nothing visible.
  function space(px) {
    const n = spaceReal(px)
    if (n <= 0) return 0

    const top = steps[steps.length - 1]
    if (n > top) return Math.round(n)

    // Nearest step, ties going to the smaller one, so a value exactly between two
    // steps does not drift upward every time it is re-read.
    let best = steps[0]
    for (let i = 1; i < steps.length; i++) {
      if (Math.abs(steps[i] - n) < Math.abs(best - n)) best = steps[i]
    }
    return best
  }

  // Every bar animation is routed through this, so reduce-motion can collapse
  // them all to zero in one place.
  property bool reduceMotion: false

  function duration(ms) {
    return reduceMotion ? 0 : ms
  }
}