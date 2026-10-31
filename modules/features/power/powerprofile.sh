#!/bin/sh
# Power profile per power source.
#
# power-profiles-daemon holds one profile at a time and has no notion of
# plugging in: something has to notice the cable move and set the other one. This
# remembers a choice per source and re-applies it — performance on mains,
# power-saver on battery, until told otherwise.
#
#   powerprofile              show the current source, profile and choices
#   powerprofile set ac P     what to use while plugged in
#   powerprofile set battery P
#   powerprofile apply        set the profile for the source we are on now
#   powerprofile automation   print whether the charge automation is on
#   powerprofile set-automation on|off
#                             toggle it at runtime; the choice is remembered in
#                             the state directory and overrides the build default
#   powerprofile charge       print the charge ceiling
#   powerprofile charge full  let it charge to 100%
#   powerprofile charge limit [N]
#                             cap charging at N% (default 80) and remember it
#                             for boot; both writes ask for root through sudo
#
# While on battery, two thresholds also dim the screen and step down the profile:
# low at @LOW@%, critical at @CRITICAL@%. The brightness before the first dim is
# saved and restored when the machine is plugged back in or the charge recovers.
# `powerprofile show` prints the thresholds and the current reading. The
# thresholds are not notifications anymore: the shell's PowerAlert sends the
# low-battery warning, so this watcher only acts.
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
AUTO_DEFAULT="@AUTO@"
LOW="@LOW@"
CRITICAL="@CRITICAL@"
AC_PROFILE="@AC_PROFILE@"
BATTERY_PROFILE="@BATTERY_PROFILE@"
LOW_PROFILE="@LOW_PROFILE@"
CRITICAL_PROFILE="@CRITICAL_PROFILE@"
LOW_BRIGHTNESS="@LOW_BRIGHTNESS@"
CRITICAL_BRIGHTNESS="@CRITICAL_BRIGHTNESS@"
CHARGE_LIMIT="@CHARGE_LIMIT@"
CHARGE_STATE="@CHARGE_STATE@"
SUDO="@SUDO@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# The build option is the default for a fresh state; once the toggle has been
# used the file wins, so turning automation off survives a rebuild.
automation_file="$STATE/automation"

automation_enabled() {
  if [ -f "$automation_file" ]; then
    case "$(cat "$automation_file" 2>/dev/null || true)" in
      on) return 0 ;;
      off) return 1 ;;
    esac
  fi
  [ "$AUTO_DEFAULT" = "1" ]
}

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

charge_ceiling() {
  for file in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
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

# The stored choice for a source, or the default.
preferred() {
  case "$1" in
    ac) fallback=$AC_PROFILE ;;
    battery) fallback=$BATTERY_PROFILE ;;
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
  mkdir -p "$STATE"

  if [ "$src" = "ac" ]; then
    restore_brightness
  elif automation_enabled; then
    percent=$(battery_percent 2>/dev/null || true)
    if [ -n "$percent" ] && [ "$percent" -le "$CRITICAL" ]; then
      profile="$CRITICAL_PROFILE"
      enter_dim critical "$CRITICAL_BRIGHTNESS"
    elif [ -n "$percent" ] && [ "$percent" -le "$LOW" ]; then
      profile="$LOW_PROFILE"
      enter_dim low "$LOW_BRIGHTNESS"
    else
      restore_brightness
    fi
  fi

  "$PPD" set "$profile" 2>/dev/null || true
  printf '%s\n' "$src" >"$STATE/last-source"
}

# The periodic check. Unlike `apply`, it does not touch the profile while the
# charge is healthy: a profile chosen by hand should survive until the cable
# moves or a threshold is crossed. It does keep the dim state honest, which is
# the part UPower's own events cannot be trusted to deliver at every percent.
#
# The source is compared here as well as in the udev listener. A missed uevent
# (or a service that started after the cable had already moved) would otherwise
# leave the machine on the other source's profile — performance on battery —
# until the next physical plug, which is exactly the case this watcher exists to
# prevent. Following a source change does not stomp on a hand-picked profile:
# `apply` still uses the stored choice for the new source.
check_battery() {
  automation_enabled || return 0

  mkdir -p "$STATE"
  src="$(source_name)"
  if [ "$(cat "$STATE/last-source" 2>/dev/null || true)" != "$src" ]; then
    apply
    return 0
  fi

  if [ "$src" = "ac" ]; then
    restore_brightness
    return 0
  fi

  percent=$(battery_percent 2>/dev/null || true)
  [ -n "$percent" ] || return 0

  if [ "$percent" -le "$CRITICAL" ]; then
    "$PPD" set "$CRITICAL_PROFILE" 2>/dev/null || true
    enter_dim critical "$CRITICAL_BRIGHTNESS"
  elif [ "$percent" -le "$LOW" ]; then
    "$PPD" set "$LOW_PROFILE" 2>/dev/null || true
    enter_dim low "$LOW_BRIGHTNESS"
  else
    restore_brightness
  fi
}

set_pref() {
  [ $# -eq 2 ] || die "set needs a source and a profile"
  mkdir -p "$STATE"
  printf '%s\n' "$2" >"$STATE/$1"
  apply
}

set_automation() {
  [ $# -eq 1 ] || die "set-automation needs on or off"
  case "$1" in
    on | off) ;;
    *) die "unknown automation state \"$1\" (want on or off)" ;;
  esac
  mkdir -p "$STATE"
  printf '%s\n' "$1" >"$automation_file"
  # Turning it off while dimmed has to put the brightness back now, not on the
  # next udev event: the watcher will not restore it once automation is off.
  if [ "$1" = "off" ]; then
    restore_brightness
  fi
  apply
}

charge() {
  [ -x "$CHARGE_LIMIT" ] || die "charge-limit is not installed; rebuild the system"
  case "${1:-show}" in
    "" | show) "$CHARGE_LIMIT" ;;
    full) "$SUDO" "$CHARGE_LIMIT" full ;;
    limit) shift; "$SUDO" "$CHARGE_LIMIT" limit "$@" ;;
    *) die "charge wants show, full or limit [N]" ;;
  esac
}

show() {
  printf 'source:  %s\n' "$(source_name)"
  printf 'profile: %s\n' "$("$PPD" get 2>/dev/null || echo unknown)"
  printf 'on mains:  %s\n' "$(preferred ac)"
  printf 'on battery: %s\n' "$(preferred battery)"
  if ceiling=$(charge_ceiling); then
    printf 'charge:    %s%% ceiling\n' "$ceiling"
    saved=$(cat "$CHARGE_STATE" 2>/dev/null || true)
    case "$saved" in
      '' | *[!0-9]*) ;;
      *) [ "$saved" = "$ceiling" ] || printf 'saved:     %s%% (not applied)\n' "$saved" ;;
    esac
  fi
  if [ -d /run/anixie/performance ]; then
    printf 'tuning:    performance extras on\n'
  else
    printf 'tuning:    default\n'
  fi
  if automation_enabled; then
    printf 'battery:   %s%%\n' "$(battery_percent 2>/dev/null || echo n/a)"
    printf 'automation: on (low %s%% -> %s at %s%%, critical %s%% -> %s at %s%%)\n' \
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
  automation) if automation_enabled; then echo on; else echo off; fi ;;
  set-automation) shift; set_automation "$@" ;;
  charge) shift; charge "$@" ;;
  watch)
    mkdir -p "$STATE"
    apply

    # udev reports the plug, the unplug and most charge changes as power-supply
    # property changes. The kernel emits a block for every property update — on
    # this battery that is several a second, and the AC/battery duplicate from
    # the kernel and udev doubles it. Acting on each line spawned
    # powerprofilesctl and brightnessctl dozens of times a second and kept the
    # CPU awake for nothing. Collect one event, compare the three values that
    # actually matter, and act only when one of them changed. The timer beside
    # it is the safety net for the events a battery does not emit.
    if on_mains; then last_online=1; else last_online=0; fi
    last_sig=
    event_has_online=
    event_online=
    event_status=
    event_capacity=
    "$UDEV" monitor --subsystem-match=power_supply --property 2>/dev/null |
      while IFS= read -r line; do
        case "$line" in
          POWER_SUPPLY_ONLINE=*)
            event_has_online=1
            event_online=${line#*=}
            ;;
          POWER_SUPPLY_STATUS=*) event_status=${line#*=} ;;
          POWER_SUPPLY_CAPACITY=*) event_capacity=${line#*=} ;;
          "")
            sig="${event_has_online:-0}:${event_online:-}|${event_status:-}|${event_capacity:-}"
            if [ -n "${event_has_online:-}${event_status:-}${event_capacity:-}${event_online:-}" ] &&
              [ "$sig" != "$last_sig" ]; then
              last_sig=$sig
              # A source change applies the stored profile for the new source
              # at once. A battery-only change just re-checks the thresholds.
              if [ -n "${event_has_online:-}" ] && [ "$event_online" != "$last_online" ]; then
                last_online=$event_online
                apply
              else
                check_battery
              fi
            fi
            event_has_online=
            event_online=
            event_status=
            event_capacity=
            ;;
        esac
      done &
    monitor=$!
    # A clean stop rather than letting the interrupted `sleep` fall through
    # `set -e` and exit 1: stopping a user service is not a failure, and the
    # status=1 the journal used to record on every logout looked like one.
    trap 'kill "$monitor" 2>/dev/null; exit 0' TERM INT

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
