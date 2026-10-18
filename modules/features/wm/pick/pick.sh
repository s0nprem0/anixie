#!/bin/sh
# The shell's picker, from a script.
#
#   pick --title theme --on-select 'theme {}'            pick a line
#   pick --title message --input --on-select 'say {}'     type a line
#   pick --title size --on-select 'transcode {} {}'       carry arguments along
#
# Reads its entries from stdin, one per line, and sends them to the shell:
#
#   label                       the value is the label
#   label<TAB>value             the value is something else
#   label<TAB>value<TAB>icon     with an icon name to draw
#   label<TAB>value<TAB>icon<TAB>state   with a trailing state to show
#
# It exits as soon as the shell has the entries, rather than when a choice is
# made, because the shell runs the choice's command itself. A caller that waited
# would be a caller with a menu on screen and no idea it had one; this way the
# script is gone before the picker is even drawn, and a multi-step flow is just
# a chain of commands, each of which may open the next picker.
#
# `--on-select` gets the chosen value spliced into it, shell-quoted by the
# shell side, so a value with a space or a quote in it cannot break the command
# it lands in.

set -eu

quickshell="@QUICKSHELL@"
jq="@JQ@"

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

die() {
  printf 'pick: %s\n' "$1" >&2
  exit 1
}

title=""
placeholder=""
mode="list"
grouped="false"
allow_empty="false"
on_select=""
on_cancel=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --title)
      [ $# -ge 2 ] || die "--title needs a value"
      title="$2"
      shift 2
      ;;
    --placeholder)
      [ $# -ge 2 ] || die "--placeholder needs a value"
      placeholder="$2"
      shift 2
      ;;
    --input)
      mode="input"
      shift
      ;;
    --allow-empty)
      allow_empty="true"
      shift
      ;;
    --grouped)
      grouped="true"
      shift
      ;;
    --on-select)
      [ $# -ge 2 ] || die "--on-select needs a command"
      on_select="$2"
      shift 2
      ;;
    --on-cancel)
      [ $# -ge 2 ] || die "--on-cancel needs a command"
      on_cancel="$2"
      shift 2
      ;;
    *)
      die "unknown argument \"$1\" (try --help)"
      ;;
  esac
done

# Everything this script makes goes away on the way out, however it leaves.
#
# One trap rather than one per file: a second `trap ... EXIT` replaces the first
# rather than adding to it, so the entries file was left behind the moment the
# request file's trap was set. The request file is not in here — the shell
# removes that one, because it is the shell that reads it.
entries_file=""
cleanup() {
  [ -n "$entries_file" ] && rm -f "$entries_file"
  return 0
}
trap cleanup EXIT

if [ "$mode" != "input" ]; then
  # The caller's lines are read into a file rather than a variable, and jq is
  # pointed at the file with --rawfile further down: the entries are the one
  # part of a request that can be arbitrarily long, and passing them as an
  # argument is what hits the kernel's per-argument cap.
  entries_file=$(mktemp)
  cat >"$entries_file"

  # Read before building the request, so a caller that has nothing to offer says
  # so here rather than opening a picker over an empty list.
  count=$("$jq" -R -s 'split("\n") | map(select(length > 0)) | length' <"$entries_file")
  [ "$count" -gt 0 ] || die "nothing to pick from"
fi

payload=$(
  "$jq" -n \
    --arg title "$title" \
    --arg placeholder "$placeholder" \
    --arg mode "$mode" \
    --arg grouped "$grouped" \
    --arg allowEmpty "$allow_empty" \
    --arg onSelect "$on_select" \
    --arg onCancel "$on_cancel" \
    --rawfile entries "$entries_file" \
    '{
      title: $title,
      placeholder: $placeholder,
      mode: $mode,
      grouped: ($grouped == "true"),
      allowEmpty: ($allowEmpty == "true"),
      onSelect: $onSelect,
      onCancel: $onCancel,
      entries: (
        $entries
        | split("\n")
        | map(select(length > 0) | split("\t"))
        | map({
            label: .[0],
            value: (.[1] // .[0]),
            icon: (.[2] // ""),
            state: (.[3] // "")
          })
      )
    }'
)

# The request goes to the shell as a file rather than as the argument itself.
# A single command-line argument is capped at 128KB by the kernel, and the emoji
# list is twice that — inline it failed with a bare "Argument list too long"
# from jq, which is a cliff to leave sitting in a picker at a size nobody can
# predict.
#
# The file is deliberately *not* removed here on the way out. The shell reads it
# asynchronously and removes it itself once it has the contents; deleting it here
# raced the read, which showed up as the picker opening under the previous
# caller's title, or not at all.
request=$(mktemp)
printf '%s' "$payload" >"$request"

# `ipc call` is synchronous, so the reply is the shell saying it has taken the
# request. A shell that is not running fails here, which is the case worth
# reporting plainly: there is nothing to pick from and no fallback — and nothing
# will read the request, so this is the one path that has to clean it up.
if ! reply=$("$quickshell" ipc call pick open "$request" 2>/dev/null); then
  rm -f "$request"
  die "the shell is not running"
fi

case "$reply" in
  ok | '"ok"' | ok.*) ;;
  *)
    rm -f "$request"
    die "the shell did not take the request${reply:+ (said: $reply)}"
    ;;
esac

exit 0