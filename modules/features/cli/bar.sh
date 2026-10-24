#!/bin/sh
# The status bar, from the command line.
#
#   bar                    this help
#   bar toggle             hide it, keeping panels and hotkeys working
#   bar on | off           show or hide it outright
#   bar position EDGE      top | bottom | left | right
#   bar move ID SECTION N  move a widget to a section and index
#   bar enable ID          put a widget back where it came from
#   bar disable ID         take it off, remembering that place
#   bar background MODE    clear | glassy | opaque
#   bar set ID KEY VALUE   one widget's setting
#   bar get ID KEY         read it back (JSON)
#   bar modules            the catalog: id, section, on/off
#   bar reload             re-read the saved layout from disk
#   bar reset              back to the shipped layout
#   bar tray               open the parked-widget drawer
#
# The bar is QML inside the running shell, so every one of these is one
# `quickshell ipc call bar` away. This command exists so `anixie bar --help` can
# describe the group instead of printing `quickshell ipc`'s own help.
set -eu

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

case "${1:-}" in
  -h | --help | "") usage; exit 0 ;;
  toggle | on | off | reset | reload | move | enable | disable | background | position | get | set | modules | tray) ;;
  *)
    printf 'bar: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac

exec "@QUICKSHELL@" ipc call bar "$@"
