#!/bin/sh
# Power profile per power source.
#
# power-profiles-daemon holds one profile at a time and has no notion of
# plugging in: something has to notice the cable move and set the other one. This
# remembers a choice per source and re-applies it — performance on mains, balanced
# on battery, until told otherwise.
#
#   powerprofile              show the current source, profile and choices
#   powerprofile set ac P     what to use while plugged in
#   powerprofile set battery P
#   powerprofile apply        set the profile for the source we are on now
#
# While on battery, two thresholds also dim the screen and step down the profile:
# low at @LOW@%, critical at @CRITICAL@%. The brightness before the first dim is
# saved and restored when the machine is plugged back in or the charge recovers.
# `powerprofile show` prints the thresholds and the current reading.
#
# The watcher (systemd user service anixie-powerprofile) runs `powerprofile watch`:
# it applies once at login, again on every udev power-supply event, and on a
# timer so a slow discharge is noticed even when no uevent is emitted. The
# battery's own charge state is the source of truth rather than UPower's
# daemon-wide onBattery flag, which stays false on this machine even on battery.
set -eu

STATE="@STATE@"
PPD="@PPD@"
UDEV="@UDEVADM@"
BRIGHTNESSCTL="@BRIGHTNESSCTL@"
NOTIFY="@NOTIFY@"
AUTO="@AUTO@"
LOW="@LOW@"
CRITICAL="@CRITICAL@"
LOW_PROFILE="@LOW_PROFILE@"
CRITICAL_PROFILE="@CRITICAL_PROFILE@"
LOW_BRIGHTNESS="@LOW_BRIGHTNESS@"
CRITICAL_BRIGHTNESS="@CRITICAL_BRIGHTNESS@"
NOTIFY_LEVEL="@NOTIFY_LEVEL@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# Mains adapters expose an `online` file; the battery does not. Any adapter
# reading 1 means the machine is plugged in.
on_mains() {
  for f in /sys/class/power_supply/*/online; do
    [ -r "$f" ] || continue
    [ "$(cat "$f" 2>/dev/null)" = "1" ] && return 0
  done
  return 1
}

source_name() {
  if on_mains; then echo ac; else echo battery; fi
}

# The first battery's charge, as a percentage. A machine with no battery simply
# has nothing to automate; the caller treats an empty reading as "leave it".
battery_percent() {
  for file in /sys/class/power_supply/BAT*/capacity; do
    [ -r "$file" ] || continue
    value=$(cat "$file" 2>/dev/null || true)
    case "$value" in
      '' | *[!0-9]*) continue ;;
    esac
    printf '%s\n' "$value"
    return 0
  done
  return 1
}

backlight_percent() {
  current=$("$BRIGHTNESSCTL" -c backlight get 2>/dev/null) || return 1
  maximum=$("$BRIGHTNESSCTL" -c backlight max 2>/dev/null) || return 1
  case "$current$maximum" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$maximum" -gt 0 ] || return 1
  printf '%s\n' "$((current * 100 / maximum))"
}

set_backlight() {
  "$BRIGHTNESSCTL" -c backlight set "$1%" >/dev/null 2>&1 || true
}

# The brightness before the first dim. It survives a profile change so that
# moving from low to critical does not save the already-dimmed value and then
# restore that when the cable goes back in.
saved_brightness="$STATE/brightness.saved"
dim_level="$STATE/brightness.level"

restore_brightness() {
  [ -f "$saved_brightness" ] || return 0
  saved=$(cat "$saved_brightness" 2>/dev/null || true)
  case "$saved" in
    '' | *[!0-9]*) ;;
    *) set_backlight "$saved" ;;
  esac
  rm -f "$saved_brightness" "$dim_level"
}

# `enter_dim LOW|CRITICAL TARGET`. The level is remembered so a user who turns
# the brightness back up while on low battery is not fought every 30 seconds;
# only crossing into a different level changes it again.
enter_dim() {
  level=$1
  target=$2
  [ "$(cat "$dim_level" 2>/dev/null || true)" = "$level" ] && return 0

  if [ ! -f "$saved_brightness" ]; then
    current=$(backlight_percent 2>/dev/null || true)
    case "$current" in
      '' | *[!0-9]*) ;;
      *) printf '%s\n' "$current" >"$saved_brightness" ;;
    esac
  fi
  set_backlight "$target"
  printf '%s\n' "$level" >"$dim_level"
}

notify_once() {
  flag=$1
  title=$2
  body=$3
  [ "$NOTIFY_LEVEL" = "0" ] && return 0
  [ -f "$flag" ] && return 0
  "$NOTIFY" -a battery -u normal -G f071 "$title" "$body" >/dev/null 2>&1 || true
  : >"$flag"
}

# The stored choice for a source, or the default.
preferred() {
  case "$1" in
    ac) fallback=performance ;;
    battery) fallback=balanced ;;
    *) die "unknown source \"$1\" (want ac or battery)" ;;
  esac
  if [ -f "$STATE/$1" ]; then
    cat "$STATE/$1"
  else
    echo "$fallback"
  fi
}

apply() {
  src="$(source_name)"
  profile="$(preferred "$src")"

  if [ "$src" = "ac" ]; then
    restore_brightness
    rm -f "$STATE/low-notified" "$STATE/critical-notified"
  elif [ "$AUTO" = "1" ]; then
    percent=$(battery_percent 2>/dev/null || true)
    if [ -n "$percent" ] && [ "$percent" -le "$CRITICAL" ]; then
      profile="$CRITICAL_PROFILE"
      enter_dim critical "$CRITICAL_BRIGHTNESS"
      notify_once "$STATE/critical-notified" "Battery critical" \
        "${percent}% left. Plug in now; the screen has been dimmed and the profile set to ${CRITICAL_PROFILE}."
      rm -f "$STATE/low-notified"
    elif [ -n "$percent" ] && [ "$percent" -le "$LOW" ]; then
      profile="$LOW_PROFILE"
      enter_dim low "$LOW_BRIGHTNESS"
      notify_once "$STATE/low-notified" "Battery low" \
        "${percent}% left. The screen has been dimmed and the profile set to ${LOW_PROFILE}."
      rm -f "$STATE/critical-notified"
    else
      restore_brightness
      rm -f "$STATE/low-notified" "$STATE/critical-notified"
    fi
  fi

  "$PPD" set "$profile" 2>/dev/null || true
}

# The periodic check. Unlike `apply`, it does not touch the profile while the
# charge is healthy: a profile chosen by hand should survive until the cable
# moves or a threshold is crossed. It does keep the dim state honest, which is
# the part UPower's own events cannot be trusted to deliver at every percent.
check_battery() {
  [ "$AUTO" = "1" ] || return 0

  src="$(source_name)"
  if [ "$src" = "ac" ]; then
    restore_brightness
    rm -f "$STATE/low-notified" "$STATE/critical-notified"
    return 0
  fi

  percent=$(battery_percent 2>/dev/null || true)
  [ -n "$percent" ] || return 0

  if [ "$percent" -le "$CRITICAL" ]; then
    "$PPD" set "$CRITICAL_PROFILE" 2>/dev/null || true
    enter_dim critical "$CRITICAL_BRIGHTNESS"
    notify_once "$STATE/critical-notified" "Battery critical" \
      "${percent}% left. Plug in now; the screen has been dimmed and the profile set to ${CRITICAL_PROFILE}."
    rm -f "$STATE/low-notified"
  elif [ "$percent" -le "$LOW" ]; then
    "$PPD" set "$LOW_PROFILE" 2>/dev/null || true
    enter_dim low "$LOW_BRIGHTNESS"
    notify_once "$STATE/low-notified" "Battery low" \
      "${percent}% left. The screen has been dimmed and the profile set to ${LOW_PROFILE}."
    rm -f "$STATE/critical-notified"
  else
    restore_brightness
    rm -f "$STATE/low-notified" "$STATE/critical-notified"
  fi
}

set_pref() {
  [ $# -eq 2 ] || die "set needs a source and a profile"
  mkdir -p "$STATE"
  printf '%s\n' "$2" >"$STATE/$1"
  apply
}

show() {
  printf 'source:  %s\n' "$(source_name)"
  printf 'profile: %s\n' "$("$PPD" get 2>/dev/null || echo unknown)"
  printf 'on mains:  %s\n' "$(preferred ac)"
  printf 'on battery: %s\n' "$(preferred battery)"
  if [ -d /run/anixie/performance ]; then
    printf 'tuning:    performance extras on\n'
  else
    printf 'tuning:    default\n'
  fi
  if [ "$AUTO" = "1" ]; then
    printf 'battery:   %s%%\n' "$(battery_percent 2>/dev/null || echo n/a)"
    printf 'automation: low %s%% -> %s at %s%%, critical %s%% -> %s at %s%%\n' \
      "$LOW" "$LOW_PROFILE" "$LOW_BRIGHTNESS" \
      "$CRITICAL" "$CRITICAL_PROFILE" "$CRITICAL_BRIGHTNESS"
  else
    printf 'automation: off\n'
  fi
}

case "${1:-}" in
  "" | show | status) show ;;
  -h | --help) usage ;;
  apply) apply ;;
  set) shift; set_pref "$@" ;;
  watch)
    mkdir -p "$STATE"
    apply

    # udev reports the plug, the unplug and most charge changes as power-supply
    # property changes. Only the relevant keys are acted on; every other line
    # falls through. The timer beside it is the safety net for the events a
    # battery does not emit.
    "$UDEV" monitor --subsystem-match=power_supply --property 2>/dev/null |
      while IFS= read -r line; do
        case "$line" in
          POWER_SUPPLY_ONLINE=* | POWER_SUPPLY_STATUS=*) apply ;;
          POWER_SUPPLY_CAPACITY=*) check_battery ;;
        esac
      done &
    monitor=$!
    trap 'kill "$monitor" 2>/dev/null' TERM INT

    while :; do
      sleep 30
      check_battery
    done
    ;;
  *)
    printf 'powerprofile: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
