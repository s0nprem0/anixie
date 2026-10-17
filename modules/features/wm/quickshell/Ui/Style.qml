pragma Singleton

import QtQuick

// Bar geometry and the spacing step. The numbers come from the reference
// design the bar is modelled on: a 26px horizontal bar whose icons are fitted
// to 12px of painted glyph rather than trusting the font's point size.
QtObject {
  readonly property QtObject font: QtObject {
    readonly property string family: "JetBrainsMono Nerd Font"
    readonly property int caption: 10
    readonly property int bodySmall: 11
    readonly property int body: 12
    readonly property int subtitle: 13
  }

  readonly property string fontFamily: font.family

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

  function space(px) {
    const n = spaceReal(px)
    return n <= 0 ? 0 : Math.max(1, Math.round(n))
  }

  // Every bar animation is routed through this, so reduce-motion can collapse
  // them all to zero in one place.
  property bool reduceMotion: false

  function duration(ms) {
    return reduceMotion ? 0 : ms
  }
}