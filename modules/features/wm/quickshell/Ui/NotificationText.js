// Text the notification card can act on: a safe link, a verification code, and
// the argv a sender attached to the click.
//
// A QML JavaScript resource rather than inline logic, because every rule here is
// about distrusting the sender: a body is arbitrary text, and the card is about
// to hand a URL to a browser or run a command. Keeping the policy in one file
// means the card and the history row cannot disagree about what is safe.

var MAX_URL = 4096
var MAX_ARGV = 32
var MAX_ARGV_TOTAL = 65536
var MAX_ACTIONS = 3
var MAX_ACTION_LABEL = 256
var MAX_ACTION_HINT = 32768

// A URL at the end of a sentence carries the punctuation, not the destination.
function trimUrl(raw) {
  var text = String(raw || "")
  function count(ch) {
    var n = 0
    for (var i = 0; i < text.length; i++) if (text.charAt(i) === ch) n++
    return n
  }
  while (text.length > 0) {
    var ch = text.charAt(text.length - 1)
    if (/[.,;:!?]/.test(ch)) { text = text.slice(0, -1); continue }
    if (ch === ")") {
      if (count("(") < count(")")) { text = text.slice(0, -1); continue }
      break
    }
    if (ch === "]" || ch === "}" || ch === "'" || ch === '"') {
      var open = ch === "]" ? "[" : (ch === "}" ? "{" : ch)
      if (count(open) < count(ch)) { text = text.slice(0, -1); continue }
      break
    }
    break
  }
  return text
}

// Only http(s), no credentials, no control characters, no quotes. This is
// deliberately narrower than a browser's URL parser: the notification only ever
// offers a link the sender already wrote in plain text.
function isValidIPv6(host) {
  if (host === "") return false
  if (!/^[0-9a-fA-F:]+$/.test(host)) return false
  if (host.indexOf(":::") !== -1) return false
  var parts = host.split("::")
  if (parts.length > 2) return false
  var groupCount = 0
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "") continue
    var groups = parts[i].split(":")
    for (var j = 0; j < groups.length; j++) {
      if (groups[j] === "") return false
      if (!/^[0-9a-fA-F]{1,4}$/.test(groups[j])) return false
      groupCount++
    }
  }
  if (parts.length === 2) {
    if (groupCount > 7) return false
  } else {
    if (groupCount !== 8) return false
  }
  return true
}

function isValidHost(host) {
  if (host === "" || host.length > 253) return false
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) {
    var octets = host.split(".")
    for (var i = 0; i < octets.length; i++) {
      if (Number(octets[i]) > 255) return false
    }
    return true
  }
  var labels = host.split(".")
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i]
    if (label === "") continue
    if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i.test(label)) return false
  }
  return true
}

function validPort(port) {
  if (!/^\d+$/.test(port)) return false
  var n = Number(port)
  return n >= 0 && n <= 65535
}

function safeUrl(raw) {
  var text = trimUrl(raw)
  if (text === "" || text.length > MAX_URL) return ""
  if (!/^https?:\/\//i.test(text)) return ""
  if (/[\x00-\x20\x7f-\x9f\\<>"']/.test(text)) return ""
  if (/^[a-z]+:\/\/[^/?#]*@/i.test(text)) return ""

  var rest = text.slice(text.match(/^https?:\/\//i)[0].length)
  var authorityEnd = rest.search(/[/?#]/)
  if (authorityEnd < 0) authorityEnd = rest.length
  var authority = rest.slice(0, authorityEnd)
  if (authority === "") return ""
  if (authority.indexOf("@") !== -1) return ""

  var host = ""
  if (authority.charAt(0) === "[") {
    var close = authority.indexOf("]")
    if (close < 1) return ""
    host = authority.slice(1, close)
    if (!isValidIPv6(host)) return ""
    var after = authority.slice(close + 1)
    if (after !== "") {
      if (after.charAt(0) !== ":") return ""
      if (!validPort(after.slice(1))) return ""
    }
  } else {
    var colonCount = (authority.match(/:/g) || []).length
    if (colonCount > 1) return ""
    if (colonCount === 1) {
      var idx = authority.indexOf(":")
      host = authority.slice(0, idx)
      if (!validPort(authority.slice(idx + 1))) return ""
    } else {
      host = authority
    }
    if (host === "" || !isValidHost(host)) return ""
  }

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
  var total = 0
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "string" || value[i].length > MAX_URL) return null
    if (value[i].indexOf("\u0000") !== -1) return null
    total += value[i].length
    if (total > MAX_ARGV_TOTAL) return null
  }
  if (value[0] === "" || value[0].charAt(0) === "-") return null
  return value
}

// Sender commands carried through history. The freedesktop action list is live
// closures into the sending client and cannot be replayed; these are argv
// arrays the shell runs itself, so a card restored from history keeps working.
// The shape is [{"label": "...", "argv": ["program", "arg"]}], never a shell
// string. At most three, because the card lays them out as one bar.
function execActions(value) {
  var parsed = value
  if (typeof value === "string") {
    if (value === "" || value.length > MAX_ACTION_HINT) return null
    try {
      parsed = JSON.parse(value)
    } catch (e) {
      return null
    }
  }
  if (!Array.isArray(parsed) || parsed.length === 0 || parsed.length > MAX_ACTIONS) return null

  var out = []
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null
    if (typeof entry.label !== "string") return null
    var label = entry.label.slice(0, MAX_ACTION_LABEL)
      .replace(/[\u0000-\u001f\u007f]+/g, " ")
      .trim()
    if (label === "") return null
    var argv = execArgv(entry.argv)
    if (!argv) return null
    out.push({ label: label, argv: argv })
  }
  return out
}

// ---- body rendering ----
//
// Senders may mark up the body; the card is about to draw it as rich text. Only
// the small set below is kept. Everything else is escaped or dropped, and a link
// still has to pass the same policy as a plain one.

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function sanitizeTag(raw) {
  var tag = String(raw || "").toLowerCase()
  if (tag === "<b>" || tag === "</b>"
      || tag === "<i>" || tag === "</i>"
      || tag === "<u>" || tag === "</u>"
      || tag === "<br>" || tag === "<br/>" || tag === "<br />") return tag
  if (/^<\/a\s*>$/.test(tag)) return "</a>"

  var href = String(raw || "").match(/^<a\s+[^>]*href\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>$/i)
  if (href) {
    var url = safeUrl(href[1] || href[2] || "")
    return url !== "" ? '<a href="' + escapeHtml(url) + '">' : ""
  }
  return ""
}

function rich(text) {
  var source = String(text || "")
  if (source.length > 32768) source = source.slice(0, 32768)

  var out = ""
  var last = 0
  var re = /<[^>]*>/g
  var match
  while ((match = re.exec(source)) !== null) {
    out += escapeHtml(source.slice(last, match.index))
    out += sanitizeTag(match[0])
    last = re.lastIndex
  }
  out += escapeHtml(source.slice(last))
  return out
}

function plain(text) {
  return String(text || "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
}

// The line a history row previews. It is deliberately plain: the panel is a
// list, not a second renderer, and tags clipped mid-row are noise.
function preview(text) {
  return plain(text).replace(/\s+/g, " ").trim()
}

// ---- sources ----
//
// A browser's app name is the browser, not the site. Chromium puts the origin in
// the leading anchor of a web notification, so a browser notification is grouped
// and iconised by the site instead of every site collapsing into "Google-chrome".
var BROWSER = /\b(chrome|chromium|firefox|librewolf|zen|brave|edge|vivaldi|helium)\b/i

function isBrowser(app) {
  return BROWSER.test(String(app || ""))
}

function hostname(url) {
  var safe = safeUrl(url)
  if (safe === "") return ""
  var match = safe.match(/^https?:\/\/([^/?#]+)/i)
  if (!match) return ""
  var authority = String(match[1])
  var host = authority
  if (host.charAt(0) === "[") {
    var close = host.indexOf("]")
    if (close < 1) return ""
    host = host.slice(1, close)
  } else {
    var colon = host.indexOf(":")
    if (colon !== -1) host = host.slice(0, colon)
  }
  host = host.toLowerCase()
  if (host.indexOf("www.") === 0) host = host.slice(4)
  return host
}

function browserSource(notification) {
  var body = String(notification && notification.body ? notification.body : "").slice(0, 32768)
  // Only the leading origin anchor Chromium adds may identify the source; a
  // link appearing later in the body or summary is content, not an origin.
  var anchor = body.match(/^\\s*<a\\b[^>]*href\\s*=\\s*["']([^"']+)["'][^>]*>/i)
  if (anchor) return hostname(anchor[1])
  // Without the anchor Chromium adds, the browser's app name is the honest answer.
  return ""
}

function source(notification) {
  if (!notification) return ""
  if (notification.sourceKey !== undefined && notification.sourceKey !== "") {
    return String(notification.source || notification.sourceKey)
  }

  var app = String(notification.appName || notification.app || "")
  if (isBrowser(app)) {
    var site = browserSource(notification)
    if (site !== "") return site
  }
  return app
}

function sourceKey(notification) {
  return source(notification).toLowerCase()
}

// A browser body starts with the origin anchor Chromium adds; the card already
// shows that origin as its source, so remove the duplicate from the body.
function displayBody(notification) {
  var body = String(notification && notification.body ? notification.body : "")
  var app = String(notification && (notification.appName || notification.app) ? (notification.appName || notification.app) : "")
  if (isBrowser(app)) body = body.replace(/^\s*<a\b[^>]*>[\s\S]*?<\/a>\s*/i, "")
  return body
}

// ---- redaction ----
//
// A verification code is useful for a few minutes and a liability in a history
// file for a day. The stored copy replaces every spelling of the detected code.
function redact(text, codeList) {
  var out = String(text || "")
  var list = Array.isArray(codeList) ? codeList : []
  for (var i = 0; i < list.length; i++) {
    var code = String(list[i] || "")
    if (code === "") continue
    var pattern = code.split("").join("[\\s-]?")
    out = out.replace(new RegExp("\\b" + pattern + "\\b", "gi"), "[code]")
  }
  return out
}

// ---- click targets ----

// Labels worth looking for in a browser title. "app.slack.com" gives "slack";
// "news.ycombinator.com" gives "news" and "ycombinator". Public suffixes and
// common subdomains are skipped so every google.com notification does not match
// the first Chrome window.
var GENERIC_LABELS = {
  www: 1, app: 1, web: 1, my: 1, m: 1, mail: 1, mobile: 1,
  com: 1, org: 1, net: 1, io: 1, co: 1, dev: 1, ai: 1, so: 1, uk: 1
}

function brands(host) {
  var labels = String(host || "").toLowerCase().split(".")
  var out = []
  for (var i = 0; i < labels.length; i++) {
    if (labels[i].length >= 4 && !Object.prototype.hasOwnProperty.call(GENERIC_LABELS, labels[i])) {
      out.push(labels[i])
      break
    }
  }
  var registered = labels.length >= 2 ? labels[labels.length - 2] : ""
  if (registered.length >= 4 && !Object.prototype.hasOwnProperty.call(GENERIC_LABELS, registered) && out.indexOf(registered) < 0) {
    out.push(registered)
  }
  return out
}

// ---- sender images ----
//
// The card is about to load a path the sender chose. A native sender can already
// read it; a sandboxed one should not be able to make the shell read a kernel
// file or another service's state. A path must be absolute, bounded, free of
// control characters and dot segments, and outside /proc, /sys, /dev, and /run
// except for this user's runtime directory.
//
// This is a lexical check only: JavaScript in this runtime cannot resolve
// symlinks, so a permitted-looking path that is a symlink into a restricted
// location is not detected here. The copy step must treat the source as
// untrusted and the OS permissions remain the real boundary.
var MAX_IMAGE_PATH = 1024
var KERNEL_PATHS = /^\/(?:proc|sys|dev)(?:\/|$)/
var RUN_PATHS = /^\/(?:var\/)?run(?:\/|$)/

function localImagePath(value) {
  var text = String(value || "")
  if (text.indexOf("image://") === 0) return ""
  if (text.indexOf("file://") === 0) {
    if (!/^file:\/\/\//i.test(text) || /[?#]/.test(text)) return ""
    try {
      text = decodeURIComponent(text.slice("file://".length))
    } catch (e) {
      return ""
    }
  }
  if (text.length === 0 || text.length > MAX_IMAGE_PATH || text.charAt(0) !== "/") return ""
  if (/[\x00-\x1f\x7f-\x9f]/.test(text)) return ""

  var parts = text.slice(1).split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "" || parts[i] === "." || parts[i] === "..") return ""
  }
  if (KERNEL_PATHS.test(text)) return ""
  if (RUN_PATHS.test(text) && !/^\/run\/user\/[0-9]+\/./.test(text)) return ""
  return text
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_URL: MAX_URL,
    MAX_ARGV: MAX_ARGV,
    MAX_ARGV_TOTAL: MAX_ARGV_TOTAL,
    MAX_ACTIONS: MAX_ACTIONS,
    MAX_ACTION_LABEL: MAX_ACTION_LABEL,
    MAX_ACTION_HINT: MAX_ACTION_HINT,
    trimUrl: trimUrl,
    safeUrl: safeUrl,
    link: link,
    execArgv: execArgv,
    execActions: execActions,
    escapeHtml: escapeHtml,
    sanitizeTag: sanitizeTag,
    rich: rich,
    plain: plain,
    preview: preview,
    isBrowser: isBrowser,
    hostname: hostname,
    browserSource: browserSource,
    source: source,
    sourceKey: sourceKey,
    displayBody: displayBody,
    redact: redact,
    code: code,
    codes: codes,
    brands: brands,
    localImagePath: localImagePath
  }
}
