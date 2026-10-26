#!/bin/sh
# Battery charge ceiling.
#
#   charge-limit             print the ceiling in effect
#   charge-limit apply       write the saved ceiling to the controller
#   charge-limit full        charge to 100% until told otherwise
#   charge-limit limit [N]   cap at N% (default 80) and remember it for boot
#
# The ceiling lives in the battery's charge controller, not on disk, so it is
# lost when the controller is reset. `apply` is what boot, resume and the
# adapter's plug event run: it reads the choice saved under /var/lib/anixie, so
# a deliberate `full` survives a reboot instead of being silently capped again.
#
# Writing the controller needs root; `powerprofile charge` runs this through
# sudo.
set -eu

BAT="@BAT@"
STATE="@STATE@"
DEFAULT="@DEFAULT@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

reading() {
  cat "$BAT" 2>/dev/null || true
}

# A write can be accepted by sysfs and still leave another value in the
# controller (firmware clamping, an EC that only supports two levels, or a
# driver that stores the request without reaching the hardware). The read-back
# is the result, so every caller checks it instead of trusting the write.
try_write() {
  [ -e "$BAT" ] || return 1
  printf '%s\n' "$1" >"$BAT" 2>/dev/null || return 1
  [ "$(reading)" = "$1" ]
}

write() {
  [ -e "$BAT" ] || die "no charge controller at $BAT"
  try_write "$1" || die "the controller reports $(reading), not $1%"
}

save() {
  mkdir -p "${STATE%/*}"
  printf '%s\n' "$1" >"$STATE"
}

case "${1:-show}" in
  "" | show) reading ;;
  apply)
    [ -e "$BAT" ] || exit 0
    limit=$DEFAULT
    if [ -r "$STATE" ]; then
      saved=$(cat "$STATE" 2>/dev/null || true)
      case "$saved" in
        '' | *[!0-9]*) ;;
        *) limit=$saved ;;
      esac
    fi
    if ! try_write "$limit"; then
      # Keep the default in place rather than leaving the battery on whatever
      # the firmware reset itself to. The saved value is deliberately left
      # alone so a later controller/firmware update can honour it.
      printf 'charge-limit: %s%% is not accepted; falling back to %s%%\n' \
        "$limit" "$DEFAULT" >&2
      write "$DEFAULT"
    fi
    ;;
  full)
    # Save only after the controller took the value, so the state file cannot
    # claim a ceiling the hardware is not actually using.
    write 100
    save 100
    ;;
  limit)
    limit=${2:-$DEFAULT}
    case "$limit" in
      '' | *[!0-9]*) die "limit wants a percentage" ;;
    esac
    if [ "$limit" -lt 40 ] || [ "$limit" -gt 100 ]; then
      die "limit must be between 40 and 100"
    fi
    write "$limit"
    save "$limit"
    ;;
  -h | --help | help) usage ;;
  *) die "unknown argument \"$1\" (try --help)" ;;
esac
