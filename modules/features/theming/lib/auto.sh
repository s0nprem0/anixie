#!/bin/sh

auto_minutes() {
  hour=${1%%:*}
  minute=${1#*:}
  hour=${hour#0}
  minute=${minute#0}
  [ -n "$hour" ] || hour=0
  [ -n "$minute" ] || minute=0
  printf '%s' "$((hour * 60 + minute))"
}

auto_mode() {
  light="${1:-07:00}"
  dark="${2:-19:00}"
  now="${3:-$(date +%H:%M)}"

  light_at=$(auto_minutes "$light")
  dark_at=$(auto_minutes "$dark")
  now_at=$(auto_minutes "$now")

  if [ "$light_at" -le "$dark_at" ]; then
    if [ "$now_at" -ge "$light_at" ] && [ "$now_at" -lt "$dark_at" ]; then
      printf 'light'
    else
      printf 'dark'
    fi
  else
    if [ "$now_at" -ge "$light_at" ] || [ "$now_at" -lt "$dark_at" ]; then
      printf 'light'
    else
      printf 'dark'
    fi
  fi
}
