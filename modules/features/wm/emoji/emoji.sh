#!/bin/sh
# The emoji picker.
#
#   emoji              pick one and type it where you are typing
#
# The list is Unicode's own emoji-test.txt, which is what a picker's emoji
# database is built from. Taking it directly means no download on first use and
# no dependency on another picker to have fetched one.
#
# Only the fully-qualified lines are listed. Every emoji appears in that file
# three or four times — as its minimally-qualified and unqualified forms, which
# exist so text presentation can be tested — and listing those would offer the
# same emoji several times over with nothing to tell them apart.
#
# The choice is typed rather than copied, because the point of picking an emoji
# is that it lands in the sentence you are writing; setting the clipboard only
# moves the work to the paste afterwards.
#
# This replaced bemoji, which did all of the above except drawing its own list —
# it shelled out to fuzzel for that, and to a downloaded database for the emoji.

set -eu

emoji_test="@EMOJI_TEST@"
wtype="@WTYPE@"

awk -F'#' '
  /; fully-qualified/ {
    # The comment is "<emoji> E<version> <name>", so the emoji is the first
    # field and the name is everything after the version.
    comment = $2
    sub(/^[ \t]+/, "", comment)

    n = split(comment, fields, /[ \t]+/)
    if (n < 3) next

    emoji = fields[1]
    name = ""
    for (i = 3; i <= n; i++) name = name (name == "" ? "" : " ") fields[i]

    printf "%s %s\t%s\n", emoji, name, emoji
  }
' "$emoji_test" | pick --title 'emoji' --on-select "$wtype {}"