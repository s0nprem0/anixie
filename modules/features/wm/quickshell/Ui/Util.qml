pragma Singleton

import QtQuick

QtObject {
  function clamp(value, min, max) {
    const n = Number(value)
    const a = Number(min)
    const b = Number(max)
    if (!isFinite(n)) return isFinite(a) ? a : 0
    if (!isFinite(a) || !isFinite(b)) return n
    if (a <= b) {
      return Math.max(a, Math.min(b, n))
    }
    return Math.max(b, Math.min(a, n))
  }

  function shellQuote(value) {
    if (value === null || value === undefined) return "''"
    const s = String(value)
    return "'" + s.replace(/'/g, "'\\''") + "'"
  }

  // A touchpad emits a stream of small deltas, and some mouse/compositor pairs
  // scale one notch well past Qt's conventional 120 units. Clamp each event,
  // then accumulate until the sum is worth a whole step and carry the remainder
  // forward.
  function wheelSteps(accumulator, delta) {
    let acc = Number(accumulator)
    let d = Number(delta)
    if (!isFinite(acc)) acc = 0
    if (!isFinite(d)) d = 0
    if (d > 120) d = 120
    if (d < -120) d = -120
    if (acc * d < 0) acc = 0

    const total = acc + d
    let steps = 0
    if (total >= 120) steps = Math.floor(total / 120)
    else if (total <= -120) steps = Math.ceil(total / 120)
    else steps = 0
    if (steps > 1) steps = 1
    if (steps < -1) steps = -1
    const remainder = total - steps * 120
    return { steps: steps, remainder: remainder }
  }

  // Icons addressed by hex code point.
  function glyph(codePoint) {
    if (codePoint === null || codePoint === undefined) return ""
    const s = String(codePoint).trim()
    if (s === "") return ""
    if (!/^[0-9a-fA-F]+$/.test(s)) return ""
    const n = parseInt(s, 16)
    if (!isFinite(n)) return ""
    if (n < 0 || n > 0x10FFFF) return ""
    // Avoid surrogate range as lone values
    if (n >= 0xD800 && n <= 0xDFFF) return ""
    // fromCharCode for compatibility; use surrogate pair for > 0xFFFF
    if (n > 0xffff) {
      return String.fromCharCode(
        0xd800 + ((n - 0x10000) >> 10),
        0xdc00 + ((n - 0x10000) & 0x3ff)
      )
    }
    return String.fromCharCode(n)
  }

  // App grid, for the launcher button.
  readonly property string menu: glyph("f00a")

  readonly property string bluetooth: glyph("f293")

  // Indicators.
  readonly property string bell: glyph("f0f3")
  readonly property string bellSlash: glyph("f1f6")
  readonly property string coffee: glyph("f0f4")
  // A bolt, for stay-awake: the caffeine icon is taken by the idle lock, and this
  // is the same idea held by logind rather than by the idle daemon.
  readonly property string bolt: glyph("f0e7")
  readonly property string moon: glyph("f186")

  // A video camera, shown while a screen recording runs.
  readonly property string record: glyph("f03d")

  // The screenshot preview: keep it on screen, or dismiss it.
  readonly property string pin: glyph("f08d")
  readonly property string close: glyph("f00d")
  readonly property string copy: glyph("f0c5")
  readonly property string annotate: glyph("f304")

  // A secured network in the Wi-Fi list.
  readonly property string lock: glyph("f023")

  // A key, for the indicator that says sudo is not asking for a password.
  readonly property string key: glyph("f084")

  // The fingerprint reader on the lock screen.
  readonly property string fingerprint: glyph("f577")

  // A laptop, for the indicator that says someone is logged in from elsewhere.
  readonly property string laptop: glyph("f109")

  // A queued reminder.
  readonly property string clock: glyph("f017")

  // A world clock: another place's time beside this one.
  readonly property string globe: glyph("f0ac")

  // The keyboard layout indicator.
  readonly property string keyboard: glyph("f11c")

  // The tree is newer than the running system.
  readonly property string update: glyph("f2f1")

  // An agent working on this machine.
  readonly property string agents: glyph("f544")

  // Service widgets.
  readonly property string dropbox: glyph("f16b")
  readonly property string video: glyph("f03d")
  readonly property string chart: glyph("f201")

  // Calendar stepping.
  readonly property string chevronLeft: glyph("f053")
  readonly property string chevronRight: glyph("f054")
  readonly property string chevronDown: glyph("f078")
  readonly property string chevronUp: glyph("f077")

  // Display brightness.
  readonly property string sun: glyph("f185")
  readonly property string star: glyph("f005")
  readonly property string starOutline: glyph("f006")
  readonly property string palette: glyph("f53f")

  readonly property string wifi: glyph("f1eb")
  readonly property string ethernet: glyph("f6ff")

  // System stats.
  readonly property string cpu: glyph("f2db")
  readonly property string memory: glyph("f538")

  // Global layout mode: a grid of tiles, and overlapping windows for the mode
  // where each window keeps its own geometry.
  readonly property string tiling: glyph("f009")
  readonly property string floating: glyph("f2d2")

  readonly property string micOn: glyph("f130")
  readonly property string micOff: glyph("f131")

  readonly property string volumeHigh: glyph("f028")
  readonly property string volumeLow: glyph("f027")
  readonly property string volumeMute: glyph("f026")

  // Media readouts, for the OSD a media key or script can ask for.
  readonly property string media: glyph("f144")
  readonly property string mediaPlay: glyph("f04b")
  readonly property string mediaPause: glyph("f04c")
  readonly property string mediaNext: glyph("f051")
  readonly property string mediaPrevious: glyph("f048")

  readonly property string batteryFull: glyph("f240")
  readonly property string batteryThreeQuarters: glyph("f241")
  readonly property string batteryHalf: glyph("f242")
  readonly property string batteryQuarter: glyph("f243")
  readonly property string batteryEmpty: glyph("f244")
  readonly property string charging: glyph("f1e6")

  // Capture actions
  readonly property string folder: glyph("f07c")
  readonly property string link: glyph("f0c1")
}