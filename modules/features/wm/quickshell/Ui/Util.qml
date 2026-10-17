pragma Singleton

import QtQuick

QtObject {
  function clamp(value, min, max) {
    const n = Number(value)
    if (!isFinite(n)) return min
    return Math.max(min, Math.min(max, n))
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  // A touchpad emits a stream of small deltas, and some mouse/compositor pairs
  // scale one notch well past Qt's conventional 120 units. Clamp each event,
  // then accumulate until the sum is worth a whole step and carry the remainder
  // forward, so a slow swipe moves one entry at a time instead of jumping.
  function wheelSteps(accumulator, delta) {
    delta = Math.max(-120, Math.min(120, delta))
    if (accumulator * delta < 0) accumulator = 0

    const total = accumulator + delta
    const steps = total < 0 ? Math.ceil(total / 120) : Math.floor(total / 120)
    return { steps: steps, remainder: total - steps * 120 }
  }

  // Icons come from the Font Awesome range, which the JetBrains Mono Nerd Font
  // ships. They are addressed by code point rather than pasted in as literals:
  // the glyphs live in the private use area, so a literal is invisible in a
  // diff and indistinguishable from an empty string at a glance.
  function glyph(codePoint) {
    const n = parseInt(codePoint, 16)
    // fromCharCode rather than fromCodePoint: the latter is an ES6 addition
    // that QML's JavaScript engine may not carry.
    return n > 0xffff
      ? String.fromCharCode(
          0xd800 + ((n - 0x10000) >> 10),
          0xdc00 + ((n - 0x10000) & 0x3ff)
        )
      : String.fromCharCode(n)
  }

  // App grid, for the launcher button.
  readonly property string menu: glyph("f00a")

  readonly property string bluetooth: glyph("f293")

  // Indicators.
  readonly property string bellSlash: glyph("f1f6")
  readonly property string coffee: glyph("f0f4")

  readonly property string wifi: glyph("f1eb")

  readonly property string micOn: glyph("f130")
  readonly property string micOff: glyph("f131")

  readonly property string volumeHigh: glyph("f028")
  readonly property string volumeLow: glyph("f027")
  readonly property string volumeMute: glyph("f026")

  readonly property string batteryFull: glyph("f240")
  readonly property string batteryThreeQuarters: glyph("f241")
  readonly property string batteryHalf: glyph("f242")
  readonly property string batteryQuarter: glyph("f243")
  readonly property string batteryEmpty: glyph("f244")
  readonly property string charging: glyph("f1e6")
}