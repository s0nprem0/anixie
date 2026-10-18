#!/bin/sh
# Set a desktop reminder.
#
#   reminder 30               in 30 minutes
#   reminder 30 "check oven"  in 30 minutes, with a message
#   reminder -i               ask for both
#   reminder show             list what is pending
#   reminder clear            drop them all
#
# A reminder is a transient systemd user timer rather than a sleeping process,
# so it outlives the shell that set it and fires whether or not anything of
# ours is still running.

set -eu

prefix="reminder"

# Interactive: the duration off a short list, the message typed. The second
# prompt is prompt-only, so fuzzel shows an input box with no list to choose
# from and returns whatever was typed.
if [ "${1:-}" = "-i" ] || [ "${1:-}" = "--interactive" ]; then
  minutes=$(printf '5\n10\n15\n30\n45\n60\n' | fuzzel --dmenu --prompt='remind in minutes: ') || exit 0
  [ -n "$minutes" ] || exit 0

  message=$(fuzzel --dmenu --prompt-only='message: ' --placeholder='optional' </dev/null) || message=""
  [ -n "$message" ] || message="Reminder"

  set -- "$minutes" "$message"
fi

case "${1:-}" in
  show | list)
    timers=$(systemctl --user list-timers --all --no-legend --no-pager "$prefix-*.timer" 2>/dev/null || true)

    if [ -z "$timers" ]; then
      printf 'No reminders set.\n'
    else
      printf '%s\n' "$timers"
    fi
    exit 0
    ;;

  count)
    # How many are pending, for the bar's indicator. A count rather than the list
    # itself so the widget is not parsing systemd's table on every poll.
    systemctl --user list-timers --all --no-legend --no-pager "$prefix-*.timer" 2>/dev/null |
      grep -c . || true
    exit 0
    ;;

  clear)
    systemctl --user list-units --all --plain --no-legend --no-pager "$prefix-*.timer" 2>/dev/null |
      awk '{ print $1 }' |
      xargs -r systemctl --user stop
    exit 0
    ;;

  "" | *[!0-9]*)
    printf 'Usage: reminder <minutes> [message] | -i | show | count | clear\n' >&2
    exit 1
    ;;
esac

minutes="$1"
shift
message="${*:-Reminder}"

# One transient timer per reminder, so they are independent and can be listed
# and stopped one at a time. --quiet keeps systemd from printing the unit name
# it made up.
#
# notify-send is named by its full path rather than left to $PATH: the timer
# runs as a service under the user manager, which does not necessarily carry
# the invoking shell's path, and systemd-run resolves the command before the
# timer is even created.
systemd-run --user --quiet \
  --unit="$prefix-$(date +%s)-$$" \
  --description="Reminder: $message" \
  --on-active="${minutes}min" \
  "@NOTIFY_SEND@" "Reminder" "$message"

printf 'Reminder in %s minute(s): %s\n' "$minutes" "$message"
