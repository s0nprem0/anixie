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
# The watcher (systemd user service anixie-powerprofile) runs `powerprofile watch`:
# it applies once at login and then again on every udev power-supply event. The
# battery's own charge state is the source of truth rather than UPower's
# daemon-wide onBattery flag, which stays false on this machine even on battery.
set -eu

STATE="@STATE@"
PPD="@PPD@"
UDEV="@UDEVADM@"

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
  "$PPD" set "$profile" 2>/dev/null || true
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
}

case "${1:-}" in
  "" | show | status) show ;;
  -h | --help) usage ;;
  apply) apply ;;
  set) shift; set_pref "$@" ;;
  watch)
    mkdir -p "$STATE"
    apply
    # udev reports the plug and the unplug as power-supply property changes. Only
    # the relevant keys are acted on; every other line falls through.
    "$UDEV" monitor --subsystem-match=power_supply --property |
      while IFS= read -r line; do
        case "$line" in
          POWER_SUPPLY_ONLINE=* | POWER_SUPPLY_STATUS=*) apply ;;
        esac
      done
    ;;
  *)
    printf 'powerprofile: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
