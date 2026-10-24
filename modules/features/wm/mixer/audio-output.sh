#!/bin/sh
# Audio output control behind one command.
#
#   audio-output set <node-id> <sink-name>
#   audio-output switch
#
# `set` is what the Audio panel calls when a sink is chosen; `switch` is the
# Shift+mute key and the volume menu. Both used to be separate binaries.
set -eu

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

case "${1:-}" in
  set)
    shift
    exec "@OUTPUT_SET@" "$@"
    ;;
  switch)
    shift
    exec "@OUTPUT_SWITCH@" "$@"
    ;;
  "" | -h | --help) usage ;;
  *)
    printf 'audio-output: unknown command "%s" (try: audio-output set|switch)\n' "$1" >&2
    exit 2
    ;;
esac
