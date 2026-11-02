#!/bin/sh
# Appearance panel.
#
#   appearance            open or close the panel
#   appearance toggle     the same
#   appearance open       open it
#   appearance close      close it
#   appearance state      the saved appearance state as JSON
#
# The panel itself lives in the shell; this is the entry point for menus,
# keybinds and scripts that cannot call the shell's IPC directly.
set -eu

quickshell="@QUICKSHELL@"

verb=${1:-toggle}
case "${1:-toggle}" in
  toggle | open | close)
    "$quickshell" ipc call appearance "$verb"
    ;;
  state)
    "$quickshell" ipc call appearance state
    ;;
  -h | --help)
    sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
    ;;
  *)
    printf 'appearance: unknown argument "%s" (try --help)\n' "$verb" >&2
    exit 2
    ;;
esac
