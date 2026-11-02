#!/bin/sh
# The menu, from a script.
#
#   menu                 the menu: every command and every application
#   menu apps            the menu, applications only
#   menu --only GROUP    one group's entries
#   menu --list [GROUP]  the entries as text, without the picker
#   menu firefox         launch an application without asking
#
# The menu is built in the shell (see quickshell/Ui/MenuHost.qml), and its keys
# reach it as Hyprland global shortcuts with no process in between. This is the
# way in for everything else — the bar's settings, a script, a test — and it is
# one `quickshell ipc call` for each.

set -eu

quickshell="@QUICKSHELL@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

call() {
  "$quickshell" ipc call menu "$@" || {
    printf 'menu: the shell is not running\n' >&2
    exit 1
  }
}

case "${1:-}" in
  "") call open ;;
  apps) call only Applications ;;
  -h | --help) usage ;;
  --only)
    [ $# -ge 2 ] || { printf 'menu: --only needs a group name\n' >&2; exit 2; }
    call only "$2"
    ;;
  --list) call list "${2:-}" ;;
  -*)
    printf 'menu: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
  *)
    reply=$(call launch "$1")
    [ "$reply" = "ok" ] || { printf 'menu: %s\n' "$reply" >&2; exit 1; }
    ;;
esac
