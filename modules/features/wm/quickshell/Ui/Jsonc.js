// JSON with comments, for user-edited config that is still mostly JSON.
//
// The shipped menu is strict JSON. The user extension beside it is the one file
// a person is expected to edit by hand, so it gets the two conveniences JSON
// lacks: // and /* */ comments, and a trailing comma before a closing brace or
// bracket. Both are stripped outside strings, so a URL or a quoted `//` is left
// alone.
//
// Kept as a plain JavaScript resource rather than inline in the QML: it is pure
// text logic, and Node can load it for tests.

function stripComments(text) {
  let out = ""
  let index = 0
  let inString = false
  let escaped = false
  let lineComment = false
  let blockComment = false

  while (index < text.length) {
    const current = text.charAt(index)
    const next = text.charAt(index + 1)

    if (lineComment) {
      if (current === "\n") {
        lineComment = false
        out += current
      }
      index += 1
      continue
    }

    if (blockComment) {
      if (current === "*" && next === "/") {
        blockComment = false
        index += 2
        continue
      }

      // Keep the newlines so a parse error still reports the right line.
      if (current === "\n") out += current
      index += 1
      continue
    }

    if (inString) {
      out += current
      if (escaped) escaped = false
      else if (current === "\\") escaped = true
      else if (current === '"') inString = false
      index += 1
      continue
    }

    if (current === '"') {
      inString = true
      out += current
      index += 1
      continue
    }

    if (current === "/" && next === "/") {
      lineComment = true
      index += 2
      continue
    }

    if (current === "/" && next === "*") {
      blockComment = true
      index += 2
      continue
    }

    out += current
    index += 1
  }

  return out
}

function stripTrailingCommas(text) {
  let out = ""
  let inString = false
  let escaped = false

  for (let index = 0; index < text.length; index++) {
    const current = text.charAt(index)

    if (inString) {
      out += current
      if (escaped) escaped = false
      else if (current === "\\") escaped = true
      else if (current === '"') inString = false
      continue
    }

    if (current === '"') {
      inString = true
      out += current
      continue
    }

    if (current === ",") {
      let next = index + 1
      while (next < text.length && /\s/.test(text.charAt(next))) next += 1
      if (text.charAt(next) === "}" || text.charAt(next) === "]") continue
    }

    out += current
  }

  return out
}

function parse(text) {
  return JSON.parse(stripTrailingCommas(stripComments(String(text || ""))))
}

if (typeof module !== "undefined") {
  module.exports = {
    stripComments: stripComments,
    stripTrailingCommas: stripTrailingCommas,
    parse: parse
  }
}
