const test = require("node:test")
const assert = require("node:assert/strict")

const State = require("../../modules/features/wm/quickshell/Ui/State.js")

test("a file with no version is treated as version 1", () => {
  assert.equal(State.versionOf({}), 1)
  assert.equal(State.versionOf({ version: 0 }), 1)
  assert.equal(State.versionOf(null), 0)
})

test("upgrading writes the current version without dropping unknown fields", () => {
  const upgraded = State.upgrade({ layout: { left: [] }, futureField: true })
  assert.equal(upgraded.version, State.VERSION)
  assert.equal(upgraded.futureField, true)
  assert.deepEqual(upgraded.layout, { left: [] })
})

test("upgrading is idempotent", () => {
  const once = State.upgrade({ a: 1 })
  const twice = State.upgrade(once)
  assert.deepEqual(twice, once)
})

test("upgrading a non-object leaves it alone", () => {
  assert.equal(State.upgrade(null), null)
  assert.equal(State.upgrade("nope"), "nope")
  assert.deepEqual(State.upgrade([1, 2]), [1, 2])
})

test("a file from a newer shell keeps its version", () => {
  const state = { version: State.VERSION + 1, future: true }
  assert.equal(State.upgrade(state).version, State.VERSION + 1)
  assert.equal(state.future, true)
})
