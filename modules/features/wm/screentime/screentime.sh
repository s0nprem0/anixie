#!/bin/sh
# Today's screen time, from the command line.
#
#   screentime            a human summary of today
#   screentime json       the stored JSON
#   screentime reset      clear today (the shell rewrites it)
#   screentime path       where today's file lives
#   screentime panel      open the shell's screen-time/focus panel
#
# The shell (Ui/ScreentimeStore.qml) does the tracking. It prefers the shell's
# live counters over IPC and falls back to the file the shell writes when it is
# restarting, so the summary is current while the shell is up and still works
# while it is not.
set -eu

state="@STATE@"
jq="@JQ@"
quickshell="@QUICKSHELL@"

day=$(date +%F)
file="$state/$day.json"

# The shell holds the live counters; the file is the last flush, up to a
# minute old. Prefer the call when the shell answers with an object, and fall
# back to the file when it is restarting.
data() {
  live=$("$quickshell" ipc call screentime status 2>/dev/null || true)
  if [ -n "$live" ] && printf '%s' "$live" | "$jq" -e 'type == "object"' >/dev/null 2>&1; then
    printf '%s' "$live"
    return 0
  fi
  if [ -s "$file" ]; then
    cat "$file"
    return 0
  fi
  return 1
}

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
    if ! payload=$(data); then
      printf 'No screen time recorded today.\n'
      exit 0
    fi
    active=$(printf '%s' "$payload" | "$jq" -r '.active // 0' 2>/dev/null || echo 0)
    idle=$(printf '%s' "$payload" | "$jq" -r '.idle // 0' 2>/dev/null || echo 0)
    printf 'date:   %s\n' "$day"
    printf 'active: %s\n' "$(format_seconds "$active")"
    printf 'idle:   %s\n' "$(format_seconds "$idle")"
    printf 'total:  %s\n' "$(format_seconds "$((active + idle))")"
    printf '\napps:\n'
    printf '%s' "$payload" |
      "$jq" -r '.apps // {} | to_entries | sort_by(-.value) | .[:8][] | "\(.value)\t\(.key)"' 2>/dev/null |
      while IFS="$(printf '\t')" read -r seconds app; do
        [ -n "$app" ] || continue
        printf '  %-10s %s\n' "$(format_seconds "$seconds")" "$app"
      done
    ;;
  json)
    if payload=$(data); then
      printf '%s\n' "$payload"
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
