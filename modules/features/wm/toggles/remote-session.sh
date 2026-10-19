#!/bin/sh
# Is anyone logged in from somewhere else?
#
#   remote-session       print "remote" or "none"
#   remote-session list  one line per session, with who and from where
#
# logind is the record of who is on the machine, and every way in ends up in it —
# SSH, a remote desktop that logs in as a session, even a second terminal. That
# is what the indicator reads, rather than any one remote tool's own state: no
# remote desktop is installed here, and the thing worth knowing is not which
# program connected but that someone did.
#
# The local seat is not a remote session. The bare-metal session and the one the
# user manager holds are both `Remote=no`, and neither is a stranger.
set -eu

LOGINCTL="@LOGINCTL@"

is_remote() {
  [ "$("$LOGINCTL" show-session "$1" -p Remote --value 2>/dev/null)" = "yes" ]
}

sessions() {
  "$LOGINCTL" list-sessions --no-legend 2>/dev/null | awk '{ print $1 }'
}

case "${1:-}" in
  "" | status)
    for session in $(sessions); do
      if is_remote "$session"; then
        printf 'remote'
        exit 0
      fi
    done
    printf 'none'
    ;;
  list)
    for session in $(sessions); do
      user="$("$LOGINCTL" show-session "$session" -p Name --value 2>/dev/null)"
      service="$("$LOGINCTL" show-session "$session" -p Service --value 2>/dev/null)"
      [ -n "$service" ] || service="-"
      printf '%s\t%s\t%s\t%s\n' "$session" "$user" "$service" "$(is_remote "$session" && echo yes || echo no)"
    done
    ;;
  *)
    printf 'remote-session: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac