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

# Tell the shell how many are queued, for the bar. Pushed after a change rather
# than asked for on a timer. Best effort: a shell that is not running is no reason
# to fail a reminder.
push_count() {
  n=$(systemctl --user list-timers --all --no-legend --no-pager "$prefix-*.timer" 2>/dev/null | grep -c . || true)
  @QUICKSHELL@ ipc call indicator reminders "${n:-0}" >/dev/null 2>&1 || true
}

# Interactive: the duration off a short list, then the message typed.
#
# Two steps rather than one process asking twice, because the picker's answer
# goes to a command the shell runs — there is no shell left here to hold the
# minutes while the second question is asked. So the first pick runs
# `reminder --ask <minutes>`, and that one asks for the message.
#
# The message is allowed to be blank, and blank means "Reminder" further down;
# without --allow-empty the picker would refuse to accept the field and there
# would be no way to take the default.
if [ "${1:-}" = "-i" ] || [ "${1:-}" = "--interactive" ]; then
  printf '5\n10\n15\n30\n45\n60\n' | pick --title 'remind in minutes' --on-select 'reminder --ask {}'
  exit 0
fi

if [ "${1:-}" = "--ask" ]; then
  [ $# -ge 2 ] || exit 1
  pick --title 'message' --placeholder 'optional' --input --allow-empty \
    --on-select "reminder $2 {}"
  exit 0
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
    push_count
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
# The app name is not decoration: NotificationHost trusts it through
# do-not-disturb, the same way it trusts the screenshot and recording
# confirmations, so a reminder the user set still speaks when the desktop is
# silenced. The glyph is the clock the bar uses for a queued reminder, and the
# command opens the history the reminder was filed in; it uses the absolute
# shell path because the command runs from the shell process, not from here.
systemd-run --user --quiet \
  --unit="$prefix-$(date +%s)-$$" \
  --description="Reminder: $message" \
  --on-active="${minutes}min" \
  "@NOTIFY_SEND@" -a reminders -u normal -G f017 \
  --exec "@QUICKSHELL@ ipc call panel toggle notifications" \
  "Reminder" "$message"

push_count

printf 'Reminder in %s minute(s): %s\n' "$minutes" "$message"
