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
#
# ---------------------------------------------------------------------------
# Why this is shaped the way it is
#
# It used to read one field at a time out of each leaf with its own jq, and
# build each row with its own jq: seven jq processes per leaf, plus one per row.
# Thirty-seven leaves and eighty-odd rows came to about 340 processes, and
# opening the menu took three seconds. The work was never the work — it was 340
# process startups.
#
# The whole tree is now flattened by one jq, the fields come back as one line
# per leaf, and the rows are assembled in the shell. The processes that are left
# are the ones that genuinely have to run — the `when` guards, the `state`
# readings and the `list` providers — and each runs once, cached by its command
# string however many entries name it.
#
# A leaf's fields are joined with 0x1f rather than a tab. bash treats tab as
# whitespace when splitting, so empty fields collapse — and a row with no icon
# and no state has three empty fields in a row. 0x1f is not whitespace, so they
# survive.

set -uo pipefail

tree="@TREE@"
quickshell="@QUICKSHELL@"
jq="@JQ@"
sh="@SH@"

# Unit separator. Not a tab: see above.
sep=$'\x1f'

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
      printf 'menu-tree: unknown argument "%s" (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
done

# The rows, as parallel arrays. Parallel rather than one array of records
# because bash has no records, and five arrays indexed the same way are what a
# record is here.
row_label=()
row_group=()
row_run=()
row_icon=()
row_state=()
declare -A seen

add_row() {
  # label, group, command, icon, state
  #
  # First wins, so a provider that returns something twice does not push a
  # second copy of it into the list. Keyed on group and label together, since
  # two groups may each have an entry of the same name.
  local key="$2 › $1"
  [ -n "${seen[$key]:-}" ] && return 0
  seen["$key"]=1

  row_label+=("$1")
  row_group+=("$2")
  row_run+=("${3:-}")
  row_icon+=("${4:-}")
  row_state+=("${5:-}")
}

# Every leaf, with the group it came from, as one line of fields.
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
flatten() {
  "$jq" -r --arg sep "$sep" '
    def walk(prefix):
      .[] |
      if has("group")
      then .group as $g | (.entries | walk(prefix + $g + " › "))
      else . + { group: (prefix | sub(" › $"; "")), path: (prefix + .label) }
      end;

    .entries
    | walk("")
    | [.path, .label, .group, (.run // ""), (.list // ""), (.state // ""), (.when // "")]
    | join($sep)
  ' "$tree"
}

# Command results, cached by the command string. Several entries can name the
# same command — the toggle states, most of all — and running it once per entry
# would put back most of the cost this file just shed.
declare -A when_result
declare -A state_result
declare -A list_result

# Run a `when` guard, once. True if it succeeded.
when_ok() {
  local cmd="$1"
  if [ -z "${when_result[$cmd]+set}" ]; then
    if "$sh" -c "$cmd" >/dev/null 2>&1; then
      when_result["$cmd"]=1
    else
      when_result["$cmd"]=0
    fi
  fi
  [ "${when_result[$cmd]}" = "1" ]
}

# A `state` command's output, once.
state_of() {
  local cmd="$1"
  if [ -z "${state_result[$cmd]+set}" ]; then
    state_result["$cmd"]=$("$sh" -c "$cmd" 2>/dev/null | tr -d '\n')
  fi
  printf '%s' "${state_result[$cmd]}"
}

# A `list` provider's output, once.
list_of() {
  local cmd="$1"
  if [ -z "${list_result[$cmd]+set}" ]; then
    list_result["$cmd"]=$("$sh" -c "$cmd" 2>/dev/null)
  fi
  printf '%s' "${list_result[$cmd]}"
}

build() {
  local path label group run_cmd list_cmd state_cmd when_cmd
  local child child_label child_icon state

  while IFS="$sep" read -r path label group run_cmd list_cmd state_cmd when_cmd; do
    [ -n "$label" ] || continue

    # A row that only makes sense some of the time says so with a command that
    # succeeds when it does. "Stop screen recording" is the reason this exists:
    # offering it with nothing recording is an entry that can only fail.
    if [ -n "$when_cmd" ] && ! when_ok "$when_cmd"; then
      continue
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
      done <<<"$(list_of "$list_cmd")"
      continue
    fi

    [ -n "$run_cmd" ] || continue

    # A command that reports the entry's state. It is carried as its own field
    # rather than appended to the label, so the picker can draw it off to the
    # side where it reads as a readout instead of as part of the name — and so
    # that the name stays the thing you search for.
    state=""
    [ -n "$state_cmd" ] && state="$(state_of "$state_cmd")"

    add_row "$label" "$group" "$run_cmd" "" "$state"
  done < <(flatten)
}

build

# Filter once, into arrays of its own, so every output below uses one set.
shown_label=()
shown_group=()
shown_run=()
shown_icon=()
shown_state=()

for i in "${!row_label[@]}"; do
  group="${row_group[$i]}"

  if [ -n "$only" ]; then
    # Prefix, not substring: `--only Style` must not pick up an entry that
    # merely mentions Style somewhere in its group.
    case "$group" in
      "$only" | "$only › "*) ;;
      *) continue ;;
    esac
  fi

  shown_label+=("${row_label[$i]}")
  shown_group+=("$group")
  shown_run+=("${row_run[$i]}")
  shown_icon+=("${row_icon[$i]}")
  shown_state+=("${row_state[$i]}")
done

if [ "${#shown_label[@]}" -eq 0 ]; then
  printf 'menu-tree: nothing to show%s\n' "${only:+ under \"$only\"}" >&2
  exit 1
fi

# The shown rows as a stream of separator-joined lines, for jq to read.
rows() {
  local i
  for i in "${!shown_label[@]}"; do
    printf '%s%s%s%s%s%s%s%s%s\n' \
      "${shown_label[$i]}" "$sep" \
      "${shown_group[$i]}" "$sep" \
      "${shown_run[$i]}" "$sep" \
      "${shown_icon[$i]}" "$sep" \
      "${shown_state[$i]}"
  done
}

# Rows to entries, in one jq rather than one per row.
entries_filter='
  split("\n")
  | map(select(length > 0))
  | map(split($sep))
  | map({ label: .[0], group: .[1], run: .[2], icon: .[3], state: .[4] })
'

if [ "$output" = "json" ]; then
  rows | "$jq" -R -s --arg sep "$sep" "$entries_filter"
  exit 0
fi

if [ "$output" = "list" ]; then
  # The human view: the same path the picker draws, with the state in
  # parentheses. This is what a test can read, and what `--only` can be checked
  # against without a picker on screen.
  for i in "${!shown_label[@]}"; do
    path="${shown_label[$i]}"
    [ -n "${shown_group[$i]}" ] && path="${shown_group[$i]} › $path"
    [ -n "${shown_state[$i]}" ] && path="$path (${shown_state[$i]})"
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
#
# The shell removes the file once it has read it — the read is asynchronous, so
# removing it here would race that read. This is the one path that has to clean
# up, because nothing else will.
request=$(mktemp)

rows | "$jq" -R -s --arg sep "$sep" --arg title "$only" '
  split("\n")
  | map(select(length > 0))
  | map(split($sep))
  | map({ label: .[0], group: .[1], run: .[2], icon: .[3], state: .[4] })
  | { title: (if $title == "" then "menu" else $title end), grouped: true, entries: . }
' >"$request"

if ! "$quickshell" ipc call pick open "$request" >/dev/null 2>&1; then
  rm -f "$request"
  printf 'menu-tree: the shell is not running\n' >&2
  exit 1
fi