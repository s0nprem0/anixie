#!/bin/sh
# Check that the anixie group table still describes the commands it names.
#
# `anixie.sh` keeps one line per group so the help, the completion and the
# dispatcher cannot disagree about which groups exist. The *subcommands*,
# though, live in each group's own dispatch case, and the table kept a second
# copy of them. The copy is what goes stale: a command grew a mode, or lost one,
# and nobody updated the list that completion reads.
#
# This reads both. For every group it finds the command's script by the first
# word of the table's command column, extracts the words its main dispatch case
# accepts (dispatch-words.awk), and compares that with the table. A word in the
# table that the command no longer accepts fails here, and so does an accepted
# word the table forgot. The only exceptions are in hidden() below: aliases and
# words only the desktop itself calls, which are real but would only be noise in
# completion.
#
# Run it from the tree root, or pass the root as the first argument.
set -eu

root=${1:-.}
cli=$root/modules/features/cli

# Accepted but deliberately not advertised. Aliases (prev/previous) and internal
# entry points (the powerprofile watcher, the picker's message callback) belong
# here; anything a person could reasonably type belongs in the table.
hidden() {
  case "$1" in
    theme) printf '%s\n' previous ;;
    update) printf '%s\n' --allow-dirty ;;
    wallpaper) printf '%s\n' pick ls add-file use previous theme default ;;
    power) printf '%s\n' watch ;;
    reminder) printf '%s\n' --interactive --ask list ;;
    snapshot) printf '%s\n' ls ;;
    *) : ;;
  esac
}

# The script behind a command name. Usually the one file of that name; `pick`
# has two (the generic picker and capture's region picker), and the group means
# the former.
script_for() {
  case "$1" in
    pick) printf '%s\n' "$root/modules/features/wm/pick/pick.sh" ;;
    monitors) printf '%s\n' "$root/modules/features/wm/display/monitors/90-dispatch.bash" ;;
    *) find "$root/modules" -name "$1.sh" -print ;;
  esac
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The table, without the assignment and its closing quote, and only the columns
# this check reads: the name, the command word, and the advertised subcommands.
sed -n "/^ANIXIE_GROUPS='/,/^'/p" "$cli/anixie.sh" |
  sed '1d;$d' |
  awk -F'|' '{ print $1 "|" $2 "|" $4 }' >"$tmp/groups"

fail=0

while IFS='|' read -r name cmd subs; do
  [ -n "$name" ] || continue

  prog=${cmd%% *}
  files=$(script_for "$prog")
  n=$(printf '%s\n' "$files" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$n" -ne 1 ]; then
    printf 'anixie: %s: expected one %s.sh under modules, found %s\n' \
      "$name" "$prog" "$n" >&2
    fail=1
    continue
  fi
  file=$files

  if ! accepted=$(awk -f "$cli/dispatch-words.awk" "$file"); then
    printf 'anixie: %s: could not read the dispatch case of %s.sh\n' \
      "$name" "$prog" >&2
    fail=1
    continue
  fi

  hidden_words=$(hidden "$name")
  for word in $hidden_words; do
    if ! printf '%s\n' "$accepted" | grep -qxF -- "$word"; then
      printf 'anixie: %s: hidden word "%s" is no longer accepted by %s.sh\n' \
        "$name" "$word" "$prog" >&2
      fail=1
    fi
  done

  expected=$(printf '%s\n' "$accepted" | awk -v hidden="$hidden_words" '
    BEGIN { n = split(hidden, a, " "); for (i = 1; i <= n; i++) skip[a[i]] = 1 }
    NF && !($0 in skip)
  ')

  printf '%s\n' "$expected" | sed '/^$/d' | sort -u >"$tmp/accepted"
  printf '%s\n' $subs | sed '/^$/d' | sort -u >"$tmp/advertised"

  if ! diff -u "$tmp/advertised" "$tmp/accepted" >"$tmp/diff"; then
    printf '\nanixie: %s: the table and %s.sh disagree\n' "$name" "$prog" >&2
    printf '  - advertised in the table only\n' >&2
    printf '  + accepted by the command only\n\n' >&2
    sed 's/^/  /' "$tmp/diff" >&2
    fail=1
  fi
done <"$tmp/groups"

if [ "$fail" -ne 0 ]; then
  printf '\nanixie: fix the table in modules/features/cli/anixie.sh, or hide the\n' >&2
  printf 'word in check-table.sh if it is not meant for completion.\n' >&2
  exit 1
fi
