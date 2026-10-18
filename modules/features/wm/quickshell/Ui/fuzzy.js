// Fuzzy matching for the shell's pickers.
//
// A QML JavaScript resource rather than a component, because it is pure logic
// with no view attached: it can be reasoned about and tested on its own, and the
// picker's job is to rank, not to draw.
//
// The scoring is fzf's, more or less. Those constants are not arbitrary — they
// come from fzf's own FuzzyMatchV2, so entries rank here the way they rank in
// every other fzf-derived picker on the system, which is what makes moving from
// fuzzel to the shell not feel like moving to something worse.
//
//     SCORE_MATCH            a character that matched at all
//     BONUS_BOUNDARY         it matched at the start of a word
//     BONUS_CAMEL            it matched inside a camelCase or digit run
//     BONUS_CONSECUTIVE      it matched right after the previous one
//     BONUS_FIRST_MULTIPLIER the first match is worth more, because a match at
//                            the very beginning is the strongest signal there is
//     PENALTY_GAP_START      a jump between two matched characters
//     PENALTY_GAP_EXTENSION  ...and each further character skipped over
//
// The gap penalties are the reason "cap" ranks "Screenshot — capture the region"
// above "Screenshot — capture to clipboard": both match c-a-p somewhere in the
// same three words, and the one that keeps them adjacent wins.

var SCORE_MATCH = 16
var BONUS_BOUNDARY = 8
var BONUS_CAMEL = 7
var BONUS_CONSECUTIVE = 8
var BONUS_FIRST_MULTIPLIER = 2
var PENALTY_GAP_START = -3
var PENALTY_GAP_EXTENSION = -1

// Matches before this many characters have been skipped without one are not
// worth counting: a query's first character may legitimately be near the end of a
// long path, and fzf caps the leading gap rather than letting it run away.
var MAX_LEADING_GAP = 24

// Character classes, for the boundary and camel bonuses.
//
// Separators score as boundaries, so a match on the "S" of "Screenshot — region"
// gets the same bonus whether it starts a path or starts a word inside one. That
// matters here because the paths are joined with "›", and treating it as a word
// character would make the menu's own separators invisible to the matcher.
function classify(ch) {
  if (ch >= "a" && ch <= "z") return 1
  if (ch >= "A" && ch <= "Z") return 2
  if (ch >= "0" && ch <= "9") return 3
  return 0
}

// The bonus for matching the character at `i`, given the text it is in. The
// original casing is needed here even though matching is done case-insensitively:
// "firefox" and "Firefox" have to match the same text, but only the second one
// offers the camel bonus on its inner capitals.
function bonusAt(text, classes, i) {
  if (i === 0) return BONUS_BOUNDARY * BONUS_FIRST_MULTIPLIER

  var prev = text.charAt(i - 1)
  var prevClass = classes[i - 1]
  var curClass = classes[i]

  if (prevClass === 0) return BONUS_BOUNDARY
  if (prevClass === 1 && curClass === 2) return BONUS_CAMEL
  if (prevClass !== 3 && curClass === 3) return BONUS_CAMEL

  return 0
}

function isSeparatorClass(c) {
  return c === 0
}

// Match `query` against `text` as a subsequence, and score it.
//
// Returns null when the query is not a subsequence at all — the query's
// characters have to appear in order, which is what makes "nlt" find
// "Night light" — and otherwise the score and the positions that earned it, so
// the caller can underline what actually matched.
function score(text, query) {
  var t = String(text)
  var q = String(query)

  if (q.length === 0) return { score: 0, positions: [] }

  var lowerT = t.toLowerCase()
  var lowerQ = q.toLowerCase()
  var n = lowerT.length
  var m = lowerQ.length

  if (m > n) return null

  // An exact hit, and a substring hit, are both worth short-circuiting: they are
  // the two cases where the ranking is not in doubt, and the menu has thousands
  // of comparisons to do on every keystroke.
  if (lowerT === lowerQ) {
    var exact = []
    for (var e = 0; e < n; e++) exact.push(e)
    return { score: SCORE_MATCH * m + 1000, positions: exact }
  }

  var at = lowerT.indexOf(lowerQ)
  if (at >= 0) {
    var contiguous = []
    for (var c = at; c < at + m; c++) contiguous.push(c)
    return {
      score: SCORE_MATCH * m + contiguous.length + (at === 0 ? 100 : 0),
      positions: contiguous
    }
  }

  var classes = new Array(n)
  for (var i = 0; i < n; i++) classes[i] = classify(t.charAt(i))

  // dp[j][i] is the best score for matching the first j+1 query characters with
  // query[j] landing exactly on text[i]. Flattened to one array per query
  // character, because a list of 80 entries × 20 query characters is 1,600 cells
  // and an object per cell would be a lot of garbage per keystroke.
  var dp = new Array(m)
  var parent = new Array(m)
  for (var j = 0; j < m; j++) {
    dp[j] = new Array(n).fill(null)
    parent[j] = new Array(n).fill(-1)
  }

  var qChar = lowerQ.charAt(0)
  for (var i0 = 0; i0 < n; i0++) {
    if (lowerT.charAt(i0) !== qChar) continue
    dp[0][i0] = SCORE_MATCH + bonusAt(t, classes, i0)
  }

  for (var j1 = 1; j1 < m; j1++) {
    var want = lowerQ.charAt(j1)
    var row = dp[j1]
    var prevRow = dp[j1 - 1]

    for (var i1 = 0; i1 < n; i1++) {
      if (lowerT.charAt(i1) !== want) continue

      var bonus = bonusAt(t, classes, i1)
      var bestScore = null
      var bestParent = -1

      // Walking backwards from the current position, so an adjacent previous
      // match is always considered before a distant one. The loop stops as soon
      // as no earlier match could win: the gap penalty only gets worse with
      // distance, so once the best available score has fallen that far behind,
      // every remaining candidate is worse too.
      for (var p = i1 - 1; p >= 0; p--) {
        var carried = prevRow[p]
        if (carried === null) continue

        var gap = i1 - p - 1
        var candidate
        if (gap === 0) {
          candidate = carried + bonus + BONUS_CONSECUTIVE
        } else {
          if (j1 === 0) continue
          var skipped = gap > MAX_LEADING_GAP ? MAX_LEADING_GAP : gap
          candidate =
            carried +
            SCORE_MATCH +
            bonus +
            PENALTY_GAP_START +
            PENALTY_GAP_EXTENSION * (skipped - 1)
        }

        if (bestScore === null || candidate > bestScore) {
          bestScore = candidate
          bestParent = p
        }
      }

      if (bestScore !== null) {
        row[i1] = bestScore
        parent[j1][i1] = bestParent
      }
    }
  }

  var best = null
  var bestAt = -1
  var last = dp[m - 1]
  for (var i2 = 0; i2 < n; i2++) {
    if (last[i2] !== null && (best === null || last[i2] > best)) {
      best = last[i2]
      bestAt = i2
    }
  }

  if (best === null) return null

  var positions = new Array(m)
  var walk = bestAt
  for (var j2 = m - 1; j2 >= 0; j2--) {
    positions[j2] = walk
    walk = parent[j2][walk]
  }

  return { score: best, positions: positions }
}

// Rank `rows` against `query`, best first.
//
// Each row is an object with a `label` to match against — the picker shows more
// than the label (a path, an icon, a state) but matches on what the user reads,
// which is the label. Rows that do not match are dropped rather than ranked
// last, so a search that matches nothing shows nothing instead of everything
// greyed out.
//
// Ties keep the order the tree was written in, and that is worth being explicit
// about rather than leaving to the engine: this JavaScript engine's Array.sort is
// not stable, so equal scores came out in an arbitrary order and opening the
// menu with an empty query showed the entries shuffled instead of in the order
// the tree lists them. Carrying the original position and breaking ties on it
// makes the default view the tree's own order, which is the one order the user
// can learn.
function filter(rows, query) {
  var out = []
  var q = String(query)

  // Nothing typed: no filtering, no sorting. The list is already the order it
  // should be in.
  if (q.length === 0) {
    for (var e = 0; e < rows.length; e++) {
      out.push({ row: rows[e], score: 0, positions: [], index: e })
    }
    return out
  }

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var label = String(row.label !== undefined ? row.label : "")
    var result = score(label, q)
    if (result !== null) out.push({ row: row, score: result.score, positions: result.positions, index: i })
  }

  out.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score
    return a.index - b.index
  })

  return out
}

// Whether `text` still matches when a fragment is added to `query`.
//
// Used for narrowing a list in steps — transcode asks for a file, then a format,
// then a size, each list filtering from what the last one left — so a fragment
// that matches nothing is caught before the picker opens on an empty list.
function matches(text, query) {
  return score(String(text), query) !== null
}