// What the menu suggests before the installed entries are ranked.
//
// Three things a launcher is expected to do with a typed query that is not an
// app name: arithmetic, opening a URL, and looking something up. The decisions
// live here as pure functions so the picker can ask once per keystroke without
// a process, and so Node can test them without a shell.
//
// File search is the one piece that cannot be a pure function — it runs fd in
// the home directory — but whether a query should trigger it is decided here.

var MIN_FILE_QUERY = 2

// A bare word with a dot is usually a file name in a launcher ("main.js"), so
// these suffixes are not treated as a domain even though the pattern would
// accept them. It is a fixed list rather than the TLD list: `.sh` and `.md` are
// real TLDs, and the person typing them at a launcher means the file.
var FILE_EXTENSIONS = [
  "js", "mjs", "cjs", "jsx", "ts", "tsx", "json", "jsonc", "md", "txt", "pdf",
  "png", "jpg", "jpeg", "gif", "svg", "webp", "mp3", "mp4", "wav", "flac",
  "zip", "tar", "gz", "nix", "py", "rs", "go", "c", "h", "cpp", "hpp", "sh",
  "bash", "zsh", "fish", "yml", "yaml", "toml", "conf", "log", "lock"
]

// A small recursive-descent calculator. No `eval`: a launcher is not a place to
// hand arbitrary text to the JavaScript engine, and this also gives a clear
// "not arithmetic" answer instead of whatever eval would have done with a file
// name.
function tokenize(input) {
  var tokens = []
  var index = 0

  while (index < input.length) {
    var ch = input.charAt(index)

    if (/\s/.test(ch)) {
      index++
      continue
    }

    if ("+-*/%^()".indexOf(ch) !== -1) {
      tokens.push(ch)
      index++
      continue
    }

    if (/[0-9.]/.test(ch)) {
      var start = index
      while (index < input.length && /[0-9.]/.test(input.charAt(index))) index++
      var text = input.slice(start, index)
      if (!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(text)) return null
      tokens.push({ number: Number(text) })
      continue
    }

    return null
  }

  return tokens
}

function parseExpression(tokens) {
  var state = { tokens: tokens, index: 0 }

  function peek() {
    return state.index < tokens.length ? tokens[state.index] : null
  }

  function take() {
    return tokens[state.index++]
  }

  function primary() {
    var token = take()
    if (token === undefined) throw new Error("unexpected end")
    if (typeof token === "object") return token.number
    if (token === "(") {
      var value = expression()
      if (take() !== ")") throw new Error("expected )")
      return value
    }
    if (token === "-") return -unary()
    if (token === "+") return unary()
    throw new Error("unexpected token")
  }

  function unary() {
    var token = peek()
    if (token === "+") {
      take()
      return unary()
    }
    if (token === "-") {
      take()
      return -unary()
    }
    return primary()
  }

  function power() {
    var base = unary()
    if (peek() === "^") {
      take()
      return Math.pow(base, power())
    }
    return base
  }

  function term() {
    var value = power()
    while (peek() === "*" || peek() === "/" || peek() === "%") {
      var op = take()
      var right = power()
      if (op === "*") value *= right
      else if (op === "/") value /= right
      else value %= right
    }
    return value
  }

  function expression() {
    var value = term()
    while (peek() === "+" || peek() === "-") {
      var op = take()
      var right = term()
      if (op === "+") value += right
      else value -= right
    }
    return value
  }

  var result = expression()
  if (state.index !== tokens.length) throw new Error("trailing input")
  return result
}

// The result of a query that is arithmetic, or null. An expression has to have
// at least one operator and one digit, so a bare number stays a search term
// instead of turning into a calculator row.
function calculator(input) {
  var text = String(input === undefined || input === null ? "" : input).trim()
  if (text === "") return null
  if (!/[0-9]/.test(text)) return null
  if (!/[+\-*/%^()]/.test(text)) return null

  var tokens
  try {
    tokens = tokenize(text)
  } catch (error) {
    return null
  }
  if (!tokens || tokens.length === 0) return null

  var value
  try {
    value = parseExpression(tokens)
  } catch (error) {
    return null
  }

  if (typeof value !== "number" || !isFinite(value)) return null

  // 0.1 + 0.2 should read 0.3, not the binary float's idea of it.
  var rounded = Math.round(value * 1e10) / 1e10
  return { value: rounded, text: String(rounded) }
}

// A URL the query already is, or null. Bare domains get https, and localhost
// gets http, which is what both expect in practice.
function urlFor(input) {
  var query = String(input === undefined || input === null ? "" : input).trim()
  if (query === "" || /\s/.test(query)) return null

  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(query)) return query

  if (/^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?(\/|$)/i.test(query)) {
    return "http://" + query
  }

  if (/^[^\s/]+\.[a-z]{2,}(:[0-9]+)?(\/.*)?$/i.test(query)) {
    const host = query.split(/[/:]/, 1)[0]
    const dot = host.lastIndexOf(".")
    const suffix = dot >= 0 ? host.slice(dot + 1).toLowerCase() : ""
    if (FILE_EXTENSIONS.indexOf(suffix) !== -1) return null
    return "https://" + query
  }

  return null
}

// A web lookup for everything that is not already a URL. DuckDuckGo is the
// default because it answers without a script-heavy front page; a different
// engine is one string here.
var SEARCH_BASE = "https://duckduckgo.com/?q="

function webUrl(query, base) {
  var text = String(query === undefined || query === null ? "" : query).trim()
  if (text === "") return ""
  return String(base || SEARCH_BASE) + encodeURIComponent(text)
}

// Whether a query is worth a file search. A URL or an expression is not, and a
// single character would match most of the home directory. A path-looking query
// is searched immediately, since there is no app called `~/`.
function shouldSearchFiles(input) {
  var query = String(input === undefined || input === null ? "" : input).trim()
  if (query === "") return false
  if (query.charAt(0) === "/" || query.charAt(0) === "~") return true
  if (query.length < MIN_FILE_QUERY) return false
  if (urlFor(query) !== null) return false
  if (calculator(query) !== null) return false
  return true
}

// The term to hand fd. A leading `~/` is the home directory, which is where fd
// already searches, so it is stripped rather than treated as a path from `/`.
function fileTerm(input) {
  var query = String(input === undefined || input === null ? "" : input).trim()
  if (query.indexOf("~/") === 0) return query.slice(2)
  if (query === "~") return ""
  return query
}

if (typeof module !== "undefined") {
  module.exports = {
    MIN_FILE_QUERY: MIN_FILE_QUERY,
    SEARCH_BASE: SEARCH_BASE,
    calculator: calculator,
    urlFor: urlFor,
    webUrl: webUrl,
    shouldSearchFiles: shouldSearchFiles,
    fileTerm: fileTerm
  }
}
