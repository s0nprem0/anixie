# Print the words a command's main dispatch case accepts, one per line.
#
# This is the other half of the table check. `anixie.sh` advertises a group's
# subcommands for help and completion; the group's own `case` is what actually
# accepts them. Reading the case is more honest than reading the prose header,
# which is prose: examples, argument names and continuation lines are not
# commands.
#
# A "main dispatch" is a case whose subject is $1 or ${1...} and which handles
# -h/--help. That is the block every command here opens with (or loops over for
# options like `record --status`). Other cases in the file — a widget's state,
# a monitor's name, a numeric range — are not dispatch and are ignored.
#
# The last such block wins: an option loop at the top of a script is followed by
# the real dispatch at the bottom, and the real dispatch is the one the table is
# written against.
#
# Words that are not commands (placeholders, ranges, the two help spellings) are
# dropped here; aliases and internal-only words are filtered by the caller.

function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}

function add(word,   i, n, parts, w) {
  gsub(/"/, "", word)
  gsub(/'/, "", word)
  n = split(word, parts, "|")
  for (i = 1; i <= n; i++) {
    w = trim(parts[i])
    if (w == "")
      continue
    if (w == "-h" || w == "--help" || w == "help") {
      has_help = 1
      continue
    }
    # Not words a user types: the catch-all, a bare flag prefix, the end of
    # options marker.
    if (w == "*" || w == "-*" || w == "--")
      continue
    # A flag with a value: --audio=WHICH completes as --audio.
    sub(/=\*$/, "", w)
    # Patterns and placeholders.
    if (w ~ /[*?[]/ || w ~ /\$/)
      continue
    if (w ~ /^[0-9]+$/)
      continue
    if (w ~ /^[A-Z]+$/)
      continue
    if (!(w in seen)) {
      seen[w] = 1
      words[++count] = w
    }
  }
}

BEGIN {
  in_case = 0
  depth = 0
}

{
  line = $0

  if (!in_case) {
    if (line ~ /^[ \t]*case[ \t].*\$1([^0-9]|$)/ ||
        line ~ /^[ \t]*case[ \t].*\$[{]1[:%}]/) {
      in_case = 1
      depth = 0
      has_help = 0
      count = 0
      delete seen
      delete words
    }
    next
  }

  if (line ~ /^[ \t]*case[ \t]/) {
    depth++
    next
  }
  if (line ~ /^[ \t]*esac/) {
    if (depth == 0) {
      if (has_help) {
        found = 1
        last_count = count
        delete last
        for (i = 1; i <= count; i++)
          last[i] = words[i]
      }
      in_case = 0
    } else {
      depth--
    }
    next
  }
  if (depth > 0)
    next
  if (line ~ /^[ \t]*#/)
    next

  # Only the pattern half of an arm: everything before its closing paren.
  if (line ~ /^[ \t]*[^ \t#][^()]*\)/) {
    pattern = line
    sub(/\).*/, "", pattern)
    add(pattern)
  }
}

END {
  if (!found) {
    print "no case handling -h/--help was found" > "/dev/stderr"
    exit 1
  }
  for (i = 1; i <= last_count; i++)
    print last[i]
}
