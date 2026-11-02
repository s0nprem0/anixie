#!/bin/sh
# Focus mode, from the command line.
#
#   focus                 the remaining time, or "off"
#   focus start [MIN]     start a block (default: the configured one)
#   focus stop            end the current block
#   focus extend [MIN]    add time to the block, or start one
#
# The timer and the app blocking live in the shell (see Ui/FocusHost.qml); this
# is the way in for a key binding, a menu entry, or a script.
set -eu

quickshell="@QUICKSHELL@"

usage() {
  cat <<'USAGE'
focus — a timed distraction block

Usage:
  focus [status]
  focus start [MINUTES]
  focus stop
  focus extend [MINUTES]
USAGE
}

case "${1:-status}" in
  -h | --help) usage ;;
  "" | status) "$quickshell" ipc call focus status ;;
  start)
    shift
    "$quickshell" ipc call focus start "${1:-}"
    ;;
  stop) "$quickshell" ipc call focus stop ;;
  extend)
    shift
    "$quickshell" ipc call focus extend "${1:-}"
    ;;
  *)
    printf 'focus: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
