#!/bin/sh
# Today's screen time, from the command line.
#
#   screentime            a human summary of today
#   screentime json       the stored JSON
#   screentime reset      clear today (the shell rewrites it)
#   screentime path       where today's file lives
#   screentime panel      open the shell's screen-time/focus panel
#
# The shell (Ui/ScreentimeStore.qml) does the tracking. This reads the file it
# writes, so it works even when the shell is restarting, and uses the shell's
# IPC only for the reset that has to clear the live counters too.
set -eu

state="@STATE@"
jq="@JQ@"
quickshell="@QUICKSHELL@"

day=$(date +%F)
file="$state/$day.json"

format_seconds() {
  total=${1:-0}
  case "$total" in
    '' | *[!0-9]*) total=0 ;;
  esac
  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  if [ "$hours" -gt 0 ]; then
    printf '%sh %sm' "$hours" "$minutes"
  else
    printf '%sm' "$minutes"
  fi
}

usage() {
  cat <<'USAGE'
screentime — screen time for today

Usage:
  screentime [show]
  screentime json
  screentime reset
  screentime path
  screentime panel
USAGE
}

case "${1:-show}" in
  -h | --help) usage ;;
  "" | show)
    if [ ! -s "$file" ]; then
      printf 'No screen time recorded today.\n'
      exit 0
    fi
    active=$("$jq" -r '.active // 0' "$file" 2>/dev/null || echo 0)
    idle=$("$jq" -r '.idle // 0' "$file" 2>/dev/null || echo 0)
    printf 'date:   %s\n' "$day"
    printf 'active: %s\n' "$(format_seconds "$active")"
    printf 'idle:   %s\n' "$(format_seconds "$idle")"
    printf 'total:  %s\n' "$(format_seconds "$((active + idle))")"
    printf '\napps:\n'
    "$jq" -r '.apps // {} | to_entries | sort_by(-.value) | .[:8][] | "\(.value)\t\(.key)"' "$file" 2>/dev/null |
      while IFS="$(printf '\t')" read -r seconds app; do
        [ -n "$app" ] || continue
        printf '  %-10s %s\n' "$(format_seconds "$seconds")" "$app"
      done
    ;;
  json)
    if [ -s "$file" ]; then
      cat "$file"
    else
      printf '{"date":"%s","apps":{},"idle":0,"active":0}\n' "$day"
    fi
    ;;
  reset)
    "$quickshell" ipc call screentime reset >/dev/null 2>&1 || rm -f "$file"
    printf 'Screen time reset for %s.\n' "$day"
    ;;
  path) printf '%s\n' "$file" ;;
  panel)
    # A saved bar layout from before the widget existed will not have it, and
    # the panel is registered by the widget. Enabling it is idempotent, so this
    # is safe whether it is already on the bar or not.
    "$quickshell" ipc call bar enable bar.screentime >/dev/null 2>&1 || true
    sleep 0.2
    "$quickshell" ipc call panel toggle screentime
    ;;
  *)
    printf 'screentime: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
