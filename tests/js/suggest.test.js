const test = require("node:test")
const assert = require("node:assert/strict")

const Suggest = require("../../modules/features/wm/quickshell/Ui/Suggest.js")

test("calculates the four operators with precedence", () => {
  assert.equal(Suggest.calculator("2+2").text, "4")
  assert.equal(Suggest.calculator("2+3*4").text, "14")
  assert.equal(Suggest.calculator("(2+3)*4").text, "20")
  assert.equal(Suggest.calculator("10 / 4").text, "2.5")
  assert.equal(Suggest.calculator("10 % 3").text, "1")
  assert.equal(Suggest.calculator("2 ^ 10").text, "1024")
})

test("rounds a floating-point artefact to what a person typed", () => {
  assert.equal(Suggest.calculator("0.1 + 0.2").text, "0.3")
})

test("negative numbers and unary signs parse", () => {
  assert.equal(Suggest.calculator("-5 + 2").text, "-3")
  assert.equal(Suggest.calculator("1 - -2").text, "3")
})

test("a bare number is a search term, not arithmetic", () => {
  assert.equal(Suggest.calculator("42"), null)
  assert.equal(Suggest.calculator(""), null)
})

test("invalid or unsafe expressions are rejected", () => {
  assert.equal(Suggest.calculator("2+"), null)
  assert.equal(Suggest.calculator("(2+3"), null)
  assert.equal(Suggest.calculator("1/0"), null)
  assert.equal(Suggest.calculator("alert(1)"), null)
  assert.equal(Suggest.calculator("1.2.3 + 1"), null)
})

test("recognises URLs and bare domains", () => {
  assert.equal(Suggest.urlFor("https://example.test/a"), "https://example.test/a")
  assert.equal(Suggest.urlFor("example.test"), "https://example.test")
  assert.equal(Suggest.urlFor("www.example.test/path"), "https://www.example.test/path")
  assert.equal(Suggest.urlFor("localhost:3000"), "http://localhost:3000")
  assert.equal(Suggest.urlFor("not a url"), null)
  assert.equal(Suggest.urlFor("firefox"), null)
})

test("a file name is not mistaken for a domain", () => {
  assert.equal(Suggest.urlFor("main.js"), null)
  assert.equal(Suggest.urlFor("notes.md"), null)
  assert.equal(Suggest.shouldSearchFiles("main.js"), true)
  assert.equal(Suggest.urlFor("example.dev"), "https://example.dev")
})

test("web URLs are encoded", () => {
  assert.equal(Suggest.webUrl("hello world"), Suggest.SEARCH_BASE + "hello%20world")
  assert.equal(Suggest.webUrl(""), "")
})

test("file search is skipped for URLs, expressions and one character", () => {
  assert.equal(Suggest.shouldSearchFiles("a"), false)
  assert.equal(Suggest.shouldSearchFiles("https://example.test"), false)
  assert.equal(Suggest.shouldSearchFiles("2+2"), false)
  assert.equal(Suggest.shouldSearchFiles("~/docs"), true)
  assert.equal(Suggest.shouldSearchFiles("/etc"), true)
  assert.equal(Suggest.shouldSearchFiles("re"), true)
})

test("a leading ~/ is stripped for fd", () => {
  assert.equal(Suggest.fileTerm("~/docs"), "docs")
  assert.equal(Suggest.fileTerm("~"), "")
  assert.equal(Suggest.fileTerm("docs"), "docs")
})
