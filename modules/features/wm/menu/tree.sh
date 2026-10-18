#!/bin/bash
# The menu: every command this shell has, in one searchable list.
#
#   menu-tree               the whole tree, in the shell's picker
#   menu-tree --only GROUP  one group's entries
#   menu-tree --list        the flat list as text, without the picker
#   menu-tree --json        the entries as JSON, without the picker
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
# Every entry carries its own command, and the picker runs it. That replaced a
# lookup keyed on the row's exact text, which meant the text a row was *drawn*
# with was also the key it was *found* by — so a state suffix on a label, or two
# rows that happened to read the same, silently changed which command ran.

set -uo pipefail

tree="@TREE@"
quickshell="@QUICKSHELL@"
jq="@JQ@"
sh="@SH@"

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

only=""
output="pick"

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
      output="list"
      shift
      ;;
    --json)
      output="json"
      shift
      ;;
    *)
      printf 'menu-tree: unknown argument "%s" (try --help)\n' >&2
      exit 2
      ;;
  esac
done

rows=()
declare -A seen

# label, group, command, icon, state
add_row() {
  # First wins, so a provider that returns something twice does not push a
  # second copy of it into the list. Keyed on group and label together, since
  # two groups may each have an entry of the same name.
  local key="$2 › $1"
  [ -n "${seen[$key]:-}" ] && return 0
  seen["$key"]=1

  rows+=("$("$jq" -nc \
    --arg label "$1" \
    --arg group "$2" \
    --arg run "${3:-}" \
    --arg icon "${4:-}" \
    --arg state "${5:-}" \
    '{ label: $label, group: $group, run: $run, icon: $icon, state: $state }')")
}

# Every leaf, with the group it came from, as one JSON object per line.
#
# Groups are recursed into and contribute to the group path; they are not rows
# themselves, because a row you can select that only opens another list is a step
# for nothing once the whole tree is searchable.
#
# The group is the accumulated prefix with its trailing separator taken back off,
# so the picker can draw it as a dimmed "Style › Theme" in front of the label
# rather than the label having to carry its own path. The path is carried too,
# because a provider's children take the whole path as their group: the
# Applications entry is a leaf with a list, not a group, so its children are
# grouped under "Applications" only by way of its own label.
#
# The group's own name is its `group` field — that is the key that marks it a
# group — and it is bound with `as $g` before the recursion rather than read as
# `.label` inside it. There, `.` is the child being walked, so `.label` is the
# child's name: reading it there built every path as "Screenshot — region ›
# Screenshot — region", and left `--only Capture` matching nothing at all.
leaves() {
  "$jq" -c '
    def walk(prefix):
      .[] |
      if has("group")
      then .group as $g | (.entries | walk(prefix + $g + " › "))
      else . + { group: (prefix | sub(" › $"; "")), path: (prefix + .label) }
      end;
    .entries | walk("")
  ' "$tree"
}

build() {
  local leaf label group path list_cmd run_cmd state_cmd when_cmd state child child_label child_icon

  while IFS= read -r leaf; do
    [ -n "$leaf" ] || continue

    label=$("$jq" -r '.label' <<<"$leaf")
    group=$("$jq" -r '.group' <<<"$leaf")
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
      # A provider: the children are whatever the command prints, one per line,
      # as "label" or "label<TAB>icon". Expanded here rather than behind a second
      # round trip, because these lists are small — themes, applications — and a
      # menu that opens in one step is worth more than one that opens lazily.
      while IFS= read -r child; do
        [ -n "$child" ] || continue

        child_label="${child%%$'\t'*}"
        child_icon=""
        case "$child" in
          *$'\t'*) child_icon="${child#*$'\t'}" ;;
        esac

        add_row "$child_label" "$path" "${run_cmd//'{}'/$child_label}" "$child_icon" ""
      done < <("$sh" -c "$list_cmd" 2>/dev/null)
      continue
    fi

    [ -n "$run_cmd" ] || continue

    # A command that reports the entry's state. It is carried as its own field
    # rather than appended to the label, so the picker can draw it off to the
    # side where it reads as a readout instead of as part of the name — and so
    # that the name stays the thing you search for.
    state=""
    if [ -n "$state_cmd" ]; then
      state=$("$sh" -c "$state_cmd" 2>/dev/null | tr -d '\n')
    fi

    add_row "$label" "$group" "$run_cmd" "" "$state"
  done < <(leaves)
}

build

shown=("${rows[@]}")
prompt="menu"

if [ -n "$only" ]; then
  # Prefix, not substring: `--only Style` must not pick up an entry that merely
  # mentions Style somewhere in its group.
  shown=()
  for row in "${rows[@]}"; do
    group=$("$jq" -r '.group' <<<"$row")
    case "$group" in
      "$only" | "$only › "*) shown+=("$row") ;;
    esac
  done
  prompt="$only"
fi

if [ "${#shown[@]}" -eq 0 ]; then
  printf 'menu-tree: nothing to show%s\n' "${only:+ under \"$only\"}" >&2
  exit 1
fi

if [ "$output" = "json" ]; then
  printf '%s\n' "${shown[@]}" | "$jq" -s .
  exit 0
fi

if [ "$output" = "list" ]; then
  # The human view: the same path the picker draws, with the state in
  # parentheses. This is what a test can read, and what `--only` can be checked
  # against without a picker on screen.
  for row in "${shown[@]}"; do
    label=$("$jq" -r '.label' <<<"$row")
    group=$("$jq" -r '.group' <<<"$row")
    state=$("$jq" -r '.state' <<<"$row")

    path="$label"
    [ -n "$group" ] && path="$group › $label"
    [ -n "$state" ] && path="$path ($state)"
    printf '%s\n' "$path"
  done
  exit 0
fi

# The picker. Every entry carries its own command, so there is no template to
# fill in and nothing to look up afterwards: the shell runs what the row says.
#
# The request goes to the shell as a file rather than as the argument itself,
# for the same reason `pick` does it: a single argument is capped at 128KB by
# the kernel, and the applications alone are a fifth of that on a small profile.
# The shell reads it synchronously, so it can go the moment the call returns.
request=$(mktemp)
trap 'rm -f "$request"' EXIT

printf '%s\n' "${shown[@]}" | "$jq" -s --arg title "$prompt" \
  '{ title: $title, grouped: true, entries: . }' >"$request"

if ! "$quickshell" ipc call pick open "$request" >/dev/null 2>&1; then
  printf 'menu-tree: the shell is not running\n' >&2
  exit 1
fi