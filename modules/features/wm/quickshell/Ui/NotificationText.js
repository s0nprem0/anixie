// Text the notification card can act on: a safe link, a verification code, and
// the argv a sender attached to the click.
//
// A QML JavaScript resource rather than inline logic, because every rule here is
// about distrusting the sender: a body is arbitrary text, and the card is about
// to hand a URL to a browser or run a command. Keeping the policy in one file
// means the card and the history row cannot disagree about what is safe.

var MAX_URL = 4096
var MAX_ARGV = 32

// A URL at the end of a sentence carries the punctuation, not the destination.
function trimUrl(raw) {
  return String(raw || "").replace(/[.,;:!?)\]}'"]+$/, "")
}

// Only http(s), no credentials, no control characters, no quotes. This is
// deliberately narrower than a browser's URL parser: the notification only ever
// offers a link the sender already wrote in plain text.
function safeUrl(raw) {
  var text = trimUrl(raw)
  if (text === "" || text.length > MAX_URL) return ""
  if (!/^https?:\/\//i.test(text)) return ""
  if (/[\x00-\x20\x7f-\x9f\\<>"']/.test(text)) return ""
  if (/^[a-z]+:\/\/[^/?#]*@/i.test(text)) return ""
  return text
}

function link(text) {
  var source = String(text || "")
  if (source.length > 32768) source = source.slice(0, 32768)
  var re = /https?:\/\/[^\s<>"']+/g
  var match
  while ((match = re.exec(source)) !== null) {
    var url = safeUrl(match[0])
    if (url !== "") return url
  }
  return ""
}

// A code is only offered when the sender names the concept. Shape alone also
// matches order numbers, ports and years, and a wrong "Copy code" is worse than
// no button.
var CODE_WORDS = /\b(code|otp|one[\s-]?time|verification|verify|passcode|pin|2fa|two[\s-]factor|security key|confirmation)\b/i
var CODE_SHAPE = /(?:^|[^\w-])((?:[A-Za-z]-)?\d{2,4}[\s-]\d{2,5}|(?:[A-Za-z]-)?\d{4,8})(?![\w-])/g
var CODE_ALNUM = /(?:^|[^\w-])([A-Z0-9]{5,8})(?![\w-])/g

function nearCodeWords(text) {
  var spans = []
  var re = new RegExp(CODE_WORDS.source, "gi")
  var match
  while ((match = re.exec(text)) !== null) {
    // "Claude Code" is a product name, not a request for a code.
    var before = text.slice(Math.max(0, match.index - 20), match.index).match(/([A-Za-z][\w.]*)\s+$/)
    if (/code/i.test(match[0]) && before && /^([A-Z][a-z]+|[A-Z]{2,})$/.test(before[1])) continue
    spans.push([Math.max(0, match.index - 24), match.index + match[0].length + 72])
    if (re.lastIndex === match.index) re.lastIndex++
  }
  return spans
}

function codes(text) {
  var source = String(text || "")
  if (source.length > 32768) source = source.slice(0, 32768)
  var spans = nearCodeWords(source)
  if (spans.length === 0) return []

  var found = []
  var seen = {}
  function take(value) {
    value = String(value || "").replace(/^[A-Za-z]-/, "").replace(/[\s-]/g, "")
    if (value.length < 4 || value.length > 8) return
    if (/^(19|20)\d\d$/.test(value)) return
    if (seen[value]) return
    seen[value] = true
    found.push(value)
  }

  for (var i = 0; i < spans.length && found.length < 4; i++) {
    var slice = source.slice(spans[i][0], spans[i][1])
    var shape = new RegExp(CODE_SHAPE.source, "g")
    var match
    while ((match = shape.exec(slice)) !== null) take(match[1])
  }
  if (found.length > 0) return found

  for (var j = 0; j < spans.length && found.length < 4; j++) {
    var rest = source.slice(spans[j][0], spans[j][1])
    var alnum = new RegExp(CODE_ALNUM.source, "g")
    var hit
    while ((hit = alnum.exec(rest)) !== null) {
      if (/\d/.test(hit[1]) && /[A-Z]/.test(hit[1])) take(hit[1])
    }
  }
  return found
}

function code(text) {
  var found = codes(text)
  return found.length > 0 ? found[0] : ""
}

// The click command is an argv array, never a shell string. A string that is not
// a valid array is not run at all: the fallback is the sender's default action
// or its window, both of which are safer than re-parsing arbitrary text.
function execArgv(value) {
  if (Array.isArray(value)) {
    var copy = []
    for (var c = 0; c < value.length; c++) {
      if (typeof value[c] !== "string") return null
      copy.push(String(value[c]))
    }
    value = copy
  } else {
    var raw = String(value || "").trim()
    if (raw === "" || raw.length > 32768) return null
    try {
      value = JSON.parse(raw)
    } catch (e) {
      return null
    }
  }

  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ARGV) return null
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string" || value[i].length > MAX_URL) return null
    if (value[i].indexOf("\u0000") !== -1) return null
  }
  if (value[0] === "" || value[0].charAt(0) === "-") return null
  return value
}
