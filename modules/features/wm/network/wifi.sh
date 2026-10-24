#!/bin/sh
# Wi-Fi control behind one command.
#
#   wifi band [auto|2.4|5|6]
#   wifi dns [set <ipv4> <ipv6>]
#   wifi password [--copy]
#   wifi qr [--password]
#
# The four operations are still separate scripts, because each owns one
# NetworkManager conversation. This front door is the only one that needs to be
# on PATH; the panel and a terminal both reach the same place through it.
set -eu

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

case "${1:-}" in
  band)
    shift
    exec "@WIFI_BAND@" "$@"
    ;;
  dns)
    shift
    exec "@WIFI_DNS@" "$@"
    ;;
  password)
    shift
    exec "@WIFI_PASSWORD@" "$@"
    ;;
  qr)
    shift
    exec "@WIFI_QR@" "$@"
    ;;
  "" | -h | --help) usage ;;
  *)
    printf 'wifi: unknown command "%s" (try: wifi band, wifi dns, wifi password, wifi qr)\n' "$1" >&2
    exit 2
    ;;
esac
