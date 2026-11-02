const test = require("node:test")
const assert = require("node:assert/strict")

const BL = require("../../modules/features/wm/quickshell/Ui/BarLayout.js")

const baseConfig = {
  version: 2,
  background: "clear",
  layout: {
    left: [{ id: "bar.menu" }],
    center: [{ id: "bar.clock", format: "HH:mm" }],
    right: [{ id: "bar.audio" }, { id: "bar.power" }]
  }
}

test("move reorders within a section", () => {
  const next = BL.move(baseConfig, "bar.power", "right", 0)
  assert.ok(next)
  assert.deepEqual(next.layout.right.map(e => e.id), ["bar.power", "bar.audio"])
  // original unchanged
  assert.deepEqual(baseConfig.layout.right.map(e => e.id), ["bar.audio", "bar.power"])
})

test("move returns null for unknown module or bad section", () => {
  assert.equal(BL.move(baseConfig, "nope", "right", 0), null)
  assert.equal(BL.move(baseConfig, "bar.audio", "nope", 0), null)
})

test("disable parks a module with origin", () => {
  const next = BL.disable(baseConfig, "bar.audio")
  assert.ok(next)
  assert.deepEqual(next.layout.right.map(e => e.id), ["bar.power"])
  assert.equal(next.disabled.length, 1)
  assert.equal(next.disabled[0].section, "right")
  assert.equal(next.disabled[0].entry.id, "bar.audio")
})

test("disable returns null when not enabled", () => {
  assert.equal(BL.disable(baseConfig, "bar.audio2"), null)
})

test("enable restores parked module", () => {
  const disabled = BL.disable(baseConfig, "bar.audio")
  const restored = BL.enable(disabled, "bar.audio", {})
  assert.ok(restored)
  assert.deepEqual(restored.layout.right.map(e => e.id), ["bar.audio", "bar.power"])
  assert.equal((restored.disabled || []).length, 0)
})

test("enable uses defaults for new module", () => {
  const next = BL.enable(baseConfig, "bar.weather", { "bar.weather": { section: "center" } })
  assert.ok(next)
  assert.deepEqual(next.layout.center.map(e => e.id), ["bar.clock", "bar.weather"])
})

test("enable returns null when already enabled", () => {
  assert.equal(BL.enable(baseConfig, "bar.clock", {}), null)
})

test("setBackground validates mode", () => {
  assert.equal(BL.setBackground(baseConfig, "glassy").background, "glassy")
  assert.equal(BL.setBackground(baseConfig, "nope"), null)
})

test("setPosition validates edge", () => {
  assert.equal(BL.setPosition(baseConfig, "left").position, "left")
  assert.equal(BL.setPosition(baseConfig, "nope"), null)
})

test("setSetting updates existing widget", () => {
  const next = BL.setSetting(baseConfig, "bar.clock", "format", "HH:mm:ss")
  assert.ok(next)
  assert.equal(next.layout.center[0].format, "HH:mm:ss")
})

test("setSetting returns null for missing widget", () => {
  assert.equal(BL.setSetting(baseConfig, "nope", "format", "x"), null)
})

test("sectionFor and catalogs", () => {
  const defaults = { "bar.weather": { section: "center" } }
  assert.equal(BL.sectionFor(baseConfig, "bar.clock", defaults), "center")
  const known = BL.knownModules(baseConfig, defaults, ["bar.clock", "bar.audio"])
  assert.ok(known.indexOf("bar.clock") !== -1)
  assert.ok(known.indexOf("bar.weather") !== -1)
  const enabled = BL.enabledModules(baseConfig)
  assert.deepEqual(enabled, ["bar.audio", "bar.clock", "bar.menu", "bar.power"])
  const available = BL.availableModules(baseConfig, defaults, ["bar.clock", "bar.audio", "bar.weather"])
  assert.ok(available.indexOf("bar.weather") !== -1)
  assert.ok(available.indexOf("bar.clock") === -1)
})

test("setScreens filters by screen", () => {
  const next = BL.setScreens(baseConfig, "bar.clock", "DP-1")
  assert.ok(next)
  const entry = next.layout.center[0]
  assert.deepEqual(entry.screens, ["DP-1"])
  assert.equal(BL.visibleOnScreens(entry, "DP-1"), true)
  assert.equal(BL.visibleOnScreens(entry, "HDMI-A-1"), false)
  const all = BL.setScreens(next, "bar.clock", null)
  assert.equal(all.layout.center[0].screens, undefined)
  assert.equal(BL.visibleOnScreens(all.layout.center[0], "DP-1"), true)
})
