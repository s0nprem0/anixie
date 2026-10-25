const test = require("node:test")
const assert = require("node:assert/strict")

const Jsonc = require("../../modules/features/wm/quickshell/Ui/Jsonc.js")

test("parses line and block comments", () => {
  const parsed = Jsonc.parse(`{
    // a note
    "a": 1, /* inline */
    "b": [1, 2] /* trailing */
  }`)
  assert.deepEqual(parsed, { a: 1, b: [1, 2] })
})

test("leaves comment markers inside strings alone", () => {
  const parsed = Jsonc.parse('{"url": "https://example.test/a//b", "note": "/* not a comment */"}')
  assert.equal(parsed.url, "https://example.test/a//b")
  assert.equal(parsed.note, "/* not a comment */")
})

test("accepts a trailing comma before a closing brace or bracket", () => {
  assert.deepEqual(Jsonc.parse('{"a": 1,}'), { a: 1 })
  assert.deepEqual(Jsonc.parse('[1, 2,]'), [1, 2])
})

test("keeps newlines from block comments so parse errors keep their line", () => {
  const stripped = Jsonc.stripComments("{\n/* one\ntwo */\n}")
  assert.equal(stripped.split("\n").length, 4)
})

test("does not treat an escaped quote as the end of a string", () => {
  const parsed = Jsonc.parse('{"quoted": "a \\" // still text"}')
  assert.equal(parsed.quoted, 'a " // still text')
})

test("rejects ordinary invalid JSON", () => {
  assert.throws(() => Jsonc.parse('{"a": }'))
})

test("an empty string is still invalid JSON rather than a silent default", () => {
  assert.throws(() => Jsonc.parse(""))
})
