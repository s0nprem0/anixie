const test = require("node:test")
const assert = require("node:assert/strict")

const Text = require("../../modules/features/wm/quickshell/Ui/NotificationText.js")

test("parses sender action commands from a hint", () => {
  const actions = Text.execActions(JSON.stringify([
    { label: "Play", argv: ["mpv", "--", "/tmp/demo.mp4"] },
    { label: "Show", argv: ["nautilus", "--select", "/tmp/demo.mp4"] }
  ]))
  assert.equal(actions.length, 2)
  assert.equal(actions[0].label, "Play")
  assert.deepEqual(actions[1].argv, ["nautilus", "--select", "/tmp/demo.mp4"])
})

test("accepts at most three actions", () => {
  const one = { label: "Do", argv: ["true"] }
  assert.equal(Text.execActions(JSON.stringify([one, one, one])).length, 3)
  assert.equal(Text.execActions(JSON.stringify([one, one, one, one])), null)
})

test("rejects unsafe or incomplete action payloads", () => {
  assert.equal(Text.execActions(""), null)
  assert.equal(Text.execActions("not json"), null)
  assert.equal(Text.execActions("[]"), null)
  assert.equal(Text.execActions(JSON.stringify([{ label: "", argv: ["true"] }])), null)
  assert.equal(Text.execActions(JSON.stringify([{ label: "No command" }])), null)
  assert.equal(Text.execActions(JSON.stringify([{ label: "Flag", argv: ["-rf", "/"] }])), null)
  assert.equal(Text.execActions(JSON.stringify([{ label: "Shell", argv: ["sh", "-c", "x"] }])).length, 1)
})

test("a stored history row keeps its action commands", () => {
  const stored = JSON.stringify([{ label: "Open", argv: ["xdg-open", "/tmp/a"] }])
  assert.deepEqual(Text.execActions(stored), [{ label: "Open", argv: ["xdg-open", "/tmp/a"] }])
})
