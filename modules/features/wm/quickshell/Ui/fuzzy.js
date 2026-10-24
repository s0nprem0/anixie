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
//
// On char codes rather than characters: `charAt` makes a one-character string
// for every comparison, and the scorer makes a great many comparisons. Past the
// end of the text — lowering can lengthen a string — charCodeAt is NaN, which
// classifies as a separator, as the empty string from charAt did.
function classify(code) {
  if (code >= 97 && code <= 122) return 1 // a-z
  if (code >= 65 && code <= 90) return 2 // A-Z
  if (code >= 48 && code <= 57) return 3 // 0-9
  return 0
}

// The bonus for matching the character at `i`. Classified from the original
// casing even though matching is done case-insensitively: "firefox" and
// "Firefox" have to match the same text, but only the second one offers the
// camel bonus on its inner capitals.
function bonusAt(text, i) {
  if (i === 0) return BONUS_BOUNDARY * BONUS_FIRST_MULTIPLIER

  var prevClass = classify(text.charCodeAt(i - 1))
  var curClass = classify(text.charCodeAt(i))

  if (prevClass === 0) return BONUS_BOUNDARY
  if (prevClass === 1 && curClass === 2) return BONUS_CAMEL
  if (prevClass !== 3 && curClass === 3) return BONUS_CAMEL

  return 0
}

// An empty cell. Scores are small integers either side of zero, so this is far
// below any real one and stands in for the null the cells used to hold.
var NONE = -2147483648

// Scratch space for the table, kept between calls. The scorer runs once per row
// per keystroke — four thousand times a key in the emoji picker — and allocating
// a table for each was a large part of what a keystroke cost. Plain arrays
// rather than typed ones, because this engine reads them faster.
var occ = []
var val = []
var par = []
var rowStart = []

// The query, lowered and split, for the run of rows it is scored against.
var lastQuery = null
var lowerQ = ""
var qChars = []

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

  if (q !== lastQuery) {
    lastQuery = q
    lowerQ = q.toLowerCase()
    qChars = new Array(lowerQ.length)
    for (var k = 0; k < lowerQ.length; k++) qChars[k] = lowerQ.charAt(k)
  }

  var lowerT = t.toLowerCase()
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

  // Not a subsequence, not a match — and the table below can only say the same
  // thing at far greater cost. In a long list this is most rows on most keys.
  // One native search per query character rather than a loop over the label's.
  var from = 0
  for (var s = 0; s < m; s++) {
    from = lowerT.indexOf(qChars[s], from)
    if (from < 0) return null
    from++
  }

  // The table has a row per query character and, in that row, a cell for each
  // place the character occurs in the text: a character can only land where it
  // is. A cell holds the best score for matching the query up to that character
  // with it landing there, and which cell of the row above that came from.
  //
  // Kept sparse because a dense row — a cell for every character of the text,
  // nearly all of them empty — is what the matcher used to fill and then walk.
  var total = 0
  for (var j = 0; j < m; j++) {
    rowStart[j] = total
    var pos = lowerT.indexOf(qChars[j])
    while (pos >= 0) {
      occ[total++] = pos
      pos = lowerT.indexOf(qChars[j], pos + 1)
    }
  }
  rowStart[m] = total

  for (var c0 = rowStart[0]; c0 < rowStart[1]; c0++) {
    val[c0] = SCORE_MATCH + bonusAt(t, occ[c0])
    par[c0] = -1
  }

  // A jump of MAX_LEADING_GAP or more skipped characters costs the same however
  // long it is, so of all the earlier matches that far back the best is simply
  // the highest-scoring one, kept as a running maximum. Only the nearer ones,
  // whose penalty still depends on the distance, are walked.
  var farPenalty = PENALTY_GAP_START + PENALTY_GAP_EXTENSION * (MAX_LEADING_GAP - 1)

  for (var j1 = 1; j1 < m; j1++) {
    var prevStart = rowStart[j1 - 1]
    var prevEnd = rowStart[j1]

    // The first cell of the row above at or past the current position, and the
    // running best of those far enough behind it. Both only move forward, since
    // the cells are in text order.
    var ahead = prevStart
    var farNext = prevStart
    var farMax = NONE
    var farArg = -1

    for (var c1 = prevEnd; c1 < rowStart[j1 + 1]; c1++) {
      var i1 = occ[c1]
      var bonus = bonusAt(t, i1)
      var bestScore = NONE
      var bestParent = -1

      while (ahead < prevEnd && occ[ahead] < i1) ahead++

      // Nearest first, so an adjacent previous match is considered before a
      // distant one and wins a tie.
      for (var p = ahead - 1; p >= prevStart; p--) {
        var gap = i1 - occ[p] - 1
        if (gap >= MAX_LEADING_GAP) break

        var carried = val[p]
        if (carried === NONE) continue

        var candidate = gap === 0
          ? carried + bonus + BONUS_CONSECUTIVE
          : carried + SCORE_MATCH + bonus + PENALTY_GAP_START + PENALTY_GAP_EXTENSION * (gap - 1)

        if (bestScore === NONE || candidate > bestScore) {
          bestScore = candidate
          bestParent = p
        }
      }

      // Ties go to the later cell, as they did when the walk ran backwards over
      // these too and only a strictly better score replaced the one it had.
      while (farNext < prevEnd && i1 - occ[farNext] - 1 >= MAX_LEADING_GAP) {
        var v = val[farNext]
        if (v !== NONE && v >= farMax) {
          farMax = v
          farArg = farNext
        }
        farNext++
      }

      if (farArg !== -1) {
        var farCandidate = farMax + SCORE_MATCH + bonus + farPenalty
        if (bestScore === NONE || farCandidate > bestScore) {
          bestScore = farCandidate
          bestParent = farArg
        }
      }

      val[c1] = bestScore
      par[c1] = bestParent
    }
  }

  var best = NONE
  var bestCell = -1
  for (var c2 = rowStart[m - 1]; c2 < rowStart[m]; c2++) {
    if (val[c2] !== NONE && (best === NONE || val[c2] > best)) {
      best = val[c2]
      bestCell = c2
    }
  }

  if (best === NONE) return null

  var positions = new Array(m)
  var cell = bestCell
  for (var j2 = m - 1; j2 >= 0; j2--) {
    positions[j2] = occ[cell]
    cell = par[cell]
  }

  return { score: best, positions: positions }
}

// Rank `rows` against `query`, best first.
//
// Each row is an object with a `label` to match against — the picker shows more
// than the label (a path, an icon, a state) but matches on what the user reads,
// which is the label. The menu additionally carries the group path it draws
// above a run of rows, and that path is matched when the label is not: typing
// "Setup" or "Capture" selects the group instead of matching nothing, without
// trying to underline characters that are not in the label. Rows that do not
// match either are dropped rather than ranked last, so a search that matches
// nothing shows nothing instead of everything greyed out.
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

    // A row can carry words that are not drawn: an application's generic name
    // and keywords. They are searched only when the label misses, so the name
    // still ranks first, while "browser" can find Firefox.
    if (result === null && row.match !== undefined && row.match !== null) {
      var match = String(row.match)
      if (match !== "") {
        var matchResult = score(match, q)
        if (matchResult !== null) result = { score: matchResult.score, positions: [] }
      }
    }

    // A menu row whose label does not match may still belong to the group the
    // query names. There is no label position to underline for that hit, so the
    // positions are empty and the group heading above the run is the feedback.
    if (result === null && row.group !== undefined && row.group !== null) {
      var group = String(row.group)
      if (group !== "") {
        var groupResult = score(group, q)
        if (groupResult !== null) result = { score: groupResult.score, positions: [] }
      }
    }

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