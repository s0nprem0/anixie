#!/bin/sh
# The clipboard history.
#
#   clipboard          pick an entry and put it back on the clipboard
#
# cliphist owns the history; this is only the choosing. `cliphist list` prints
# "<id>\t<preview>" per line, so the preview is what you read and the id is what
# the picker hands back — a row's text and the thing it means are not the same
# here, which is what the picker's value field is for. It used to work by piping
# the same text through fuzzel and feeding whatever came out back to cliphist,
# which meant the id had to survive a round trip through a line of display text.
#
# awk rather than a tab-splitting read loop: a preview can contain tabs, so the
# only safe split is on the *first* one. Entries without one are skipped rather
# than guessed at, since an entry that cannot be decoded is worse than one that
# is not offered.

set -eu

cliphist="@CLIPHIST@"
wl_copy="@WL_COPY@"

"$cliphist" list | awk '
  {
    tab = index($0, "\t")
    if (tab == 0) next
    printf "%s\t%s\n", substr($0, tab + 1), substr($0, 1, tab - 1)
  }
' | pick --title 'clipboard' --on-select "$cliphist decode {} | $wl_copy"