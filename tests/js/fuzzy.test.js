const test = require("node:test")
const assert = require("node:assert/strict")

const Fuzzy = require("../../modules/features/wm/quickshell/Ui/fuzzy.js")

test("exact and substring matches beat a scattered subsequence", () => {
  const exact = Fuzzy.score("Files", "Files")
  const substring = Fuzzy.score("Files", "ile")
  const scattered = Fuzzy.score("File manager", "fm")

  assert.ok(exact)
  assert.ok(substring)
  assert.ok(scattered)
  assert.ok(exact.score > substring.score)
  assert.ok(substring.score > scattered.score)
})

test("a query that is not a subsequence does not match", () => {
  assert.equal(Fuzzy.score("abc", "ca"), null)
  assert.equal(Fuzzy.score("firefox", "of"), null)
  assert.equal(Fuzzy.score("short", "much longer query"), null)
})

test("matching is case insensitive", () => {
  assert.ok(Fuzzy.score("Firefox", "FIRE"))
  assert.ok(Fuzzy.score("firefox", "Fire"))
})

test("positions point at the characters the match used", () => {
  const result = Fuzzy.score("Screenshot", "sc")
  assert.deepEqual(result.positions, [0, 1])
})

test("an empty query matches everything in order and does not sort", () => {
  const rows = [{ label: "b" }, { label: "a" }]
  const out = Fuzzy.filter(rows, "")
  assert.deepEqual(out.map((entry) => entry.row.label), ["b", "a"])
  assert.deepEqual(out[0].positions, [])
})

test("filter drops non-matches and keeps the best first", () => {
  const rows = [
    { label: "Screenshot — capture to clipboard" },
    { label: "Screenshot — capture the region" },
    { label: "Firefox" }
  ]
  const out = Fuzzy.filter(rows, "reg")
  assert.equal(out.length, 1)
  assert.match(out[0].row.label, /region/)
})

test("a row's match words are searched only when the label misses", () => {
  const rows = [
    { label: "Firefox", match: "browser web" },
    { label: "Files" }
  ]
  const out = Fuzzy.filter(rows, "browser")
  assert.equal(out.length, 1)
  assert.equal(out[0].row.label, "Firefox")
})

test("a row can be found by its group when its label does not match", () => {
  const rows = [{ label: "Audio", group: "Setup › Sound" }]
  const out = Fuzzy.filter(rows, "sound")
  assert.equal(out.length, 1)
  assert.deepEqual(out[0].positions, [])
})

test("equal scores keep the order they were given in", () => {
  const rows = [{ label: "Alpha" }, { label: "Alpha" }]
  const out = Fuzzy.filter(rows, "alpha")
  assert.deepEqual(out.map((entry) => entry.index), [0, 1])
})
