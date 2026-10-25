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

write() {
  [ -e "$BAT" ] || die "no charge controller at $BAT"
  printf '%s\n' "$1" >"$BAT"
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
    write "$limit"
    ;;
  full)
    save 100
    write 100
    ;;
  limit)
    limit=${2:-$DEFAULT}
    case "$limit" in
      '' | *[!0-9]*) die "limit wants a percentage" ;;
    esac
    if [ "$limit" -lt 40 ] || [ "$limit" -gt 100 ]; then
      die "limit must be between 40 and 100"
    fi
    save "$limit"
    write "$limit"
    ;;
  -h | --help | help) usage ;;
  *) die "unknown argument \"$1\" (try --help)" ;;
esac
