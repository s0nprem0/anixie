#!/bin/bash
# The menu: every command this shell has, in one searchable list.
#
#   menu-tree               the whole tree
#   menu-tree --only GROUP   one group's entries
#   menu-tree --list        the flat list, without the picker
#
# The tree is flattened rather than navigated. A hierarchy that you walk one
# level at a time makes you remember where a thing lives; flattening it and
# searching the whole thing at once does not — typing "theme" finds every theme
# from the top, and "night" finds the night light without knowing it is under
# Toggle. The path is still shown, so the shape is visible as you search.
#
# Groups are a *prefix* on that path, not a place you have to be. That is what
# lets `--only Capture` be the same menu with a filter rather than a second list
# of the same commands kept in step by hand.
#
# The tree itself is a JSON file, so adding an entry is a line in it. `list`
# makes a group's children come from a command's output, which is how the themes
# and the applications get in without being written out here.
#
# One row is one line, and the line *is* the key: the command for it is looked up
# by the exact text fuzzel returns, so nothing has to be parsed back out.

set -uo pipefail

tree="@TREE@"
fuzzel="@FUZZEL@"
jq="@JQ@"
sh="@SH@"
setsid="@SETSID@"

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

only=""
list_only="false"

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --only)
      [ $# -ge 2 ] || { printf 'menu-tree: --only needs a group name\n' >&2; exit 2; }
      only="$2"
      shift 2
      ;;
    --list)
      list_only="true"
      shift
      ;;
    *)
      printf 'menu-tree: unknown argument "%s" (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
done

# label -> command. A bash associative array rather than a second file, because
# the two are built together and must not drift.
declare -A command_of
rows=()

add_row() {
  # First wins, so a provider that returns something twice does not push a
  # second copy of it into the list.
  [ -n "${command_of[$1]:-}" ] && return 0
  command_of["$1"]="$2"
  rows+=("$1")
}

# Every leaf, with its path, as one JSON object per line. Groups are recursed
# into and contribute their label to the path; they are not rows themselves,
# because a row you can select that only opens another list is a step for
# nothing once the whole tree is searchable.
#
# The group's own name is its `group` field — that is the key that marks it a
# group — and it is bound with `as $g` before the recursion rather than read as
# `.label` inside it. There, `.` is the child being walked, so `.label` is the
# child's name: reading it there built every path as "Screenshot — region ›
# Screenshot — region", and left `--only Capture` matching nothing at all,
# because no path began with "Capture".
leaves() {
  "$jq" -c '
    def walk(prefix):
      .[] |
      if has("group")
      then .group as $g | (.entries | walk(prefix + $g + " › "))
      else . + { path: (prefix + .label) }
      end;
    .entries | walk("")
  ' "$tree"
}

build() {
  local leaf path list_cmd run_cmd state_cmd when_cmd state child

  while IFS= read -r leaf; do
    [ -n "$leaf" ] || continue

    path=$("$jq" -r '.path' <<<"$leaf")
    list_cmd=$("$jq" -r '.list // empty' <<<"$leaf")
    run_cmd=$("$jq" -r '.run // empty' <<<"$leaf")
    state_cmd=$("$jq" -r '.state // empty' <<<"$leaf")
    when_cmd=$("$jq" -r '.when // empty' <<<"$leaf")

    # A row that only makes sense some of the time says so with a command that
    # succeeds when it does. "Stop screen recording" is the reason this exists:
    # offering it with nothing recording is an entry that can only fail.
    if [ -n "$when_cmd" ]; then
      "$sh" -c "$when_cmd" >/dev/null 2>&1 || continue
    fi

    if [ -n "$list_cmd" ]; then
      # A provider: the children are whatever the command prints. Expanded here
      # rather than behind a second round trip, because these lists are small —
      # themes, applications — and a menu that opens in one step is worth more
      # than one that opens lazily.
      while IFS= read -r child; do
        [ -n "$child" ] || continue
        add_row "$path › $child" "${run_cmd//'{}'/$child}"
      done < <("$sh" -c "$list_cmd" 2>/dev/null)
      continue
    fi

    [ -n "$run_cmd" ] || continue

    # A command that reports the entry's state, shown in the label. This is what
    # makes the menu a readout as well as a switch: the toggles say whether they
    # are on before you pick one, so the list answers the question you opened it
    # with.
    if [ -n "$state_cmd" ]; then
      state=$("$sh" -c "$state_cmd" 2>/dev/null | tr -d '\n')
      [ -n "$state" ] && path="$path ($state)"
    fi

    add_row "$path" "$run_cmd"
  done < <(leaves)
}

build

shown=("${rows[@]}")
prompt="menu  "

if [ -n "$only" ]; then
  # Prefix, not substring: `--only Style` must not pick up an entry that merely
  # mentions Style somewhere in its path.
  shown=()
  for row in "${rows[@]}"; do
    case "$row" in
      "$only" | "$only › "*) shown+=("$row") ;;
    esac
  done
  prompt="$only  "
fi

# After the filter, so `--list --only Capture` shows what that key would show
# rather than the whole tree with the filter quietly dropped.
if [ "$list_only" = "true" ]; then
  [ ${#shown[@]} -gt 0 ] && printf '%s\n' "${shown[@]}"
  exit 0
fi

if [ ${#shown[@]} -eq 0 ]; then
  printf 'menu-tree: nothing to show%s\n' "${only:+ under \"$only\"}" >&2
  exit 1
fi

choice=$(printf '%s\n' "${shown[@]}" | "$fuzzel" --dmenu --prompt="$prompt" --width 60 --lines 14) || exit 0
[ -n "$choice" ] || exit 0

command="${command_of[$choice]:-}"
if [ -z "$command" ]; then
  printf 'menu-tree: no command for "%s"\n' "$choice" >&2
  exit 1
fi

# Detached, because half of these open something that outlives the menu — a
# picker, a terminal, a recording — and the menu should be gone by then rather
# than sitting in the background holding it.
"$setsid" -f "$sh" -c "$command" >/dev/null 2>&1
