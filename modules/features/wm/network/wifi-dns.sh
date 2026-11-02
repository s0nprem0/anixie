#!/usr/bin/env bash
set -euo pipefail

nmcli="@NMCLI@"

nm_get() {
  LC_ALL=C "$nmcli" -e no -g "$@" 2>/dev/null
}

wifi_device() {
  nm_get DEVICE,TYPE,STATE device status |
    awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }'
}

wifi_profile() {
  nm_get GENERAL.CONNECTION device show "$1"
}

print_status() {
  local device profile

  device=$(wifi_device)
  [[ -n "$device" ]] || return 0

  profile=$(wifi_profile "$device")
  [[ -n "$profile" ]] || return 0

  printf 'ipv4\t%s\n' "$(nm_get ipv4.dns connection show "$profile")"
  printf 'ipv6\t%s\n' "$(nm_get ipv6.dns connection show "$profile")"
}

set_dns() {
  local v4="$1"
  local v6="$2"
  local device profile
  local previous4 previous6 previous_ignore4 previous_ignore6
  local ignore4 ignore6

  device=$(wifi_device)
  [[ -n "$device" ]] || {
    echo "wifi-dns: no connected Wi-Fi device" >&2
    exit 1
  }

  profile=$(wifi_profile "$device")
  [[ -n "$profile" ]] || {
    echo "wifi-dns: no active Wi-Fi profile" >&2
    exit 1
  }

  previous4=$(nm_get ipv4.dns connection show "$profile")
  previous6=$(nm_get ipv6.dns connection show "$profile")
  previous_ignore4=$(nm_get ipv4.ignore-auto-dns connection show "$profile" || true)
  previous_ignore6=$(nm_get ipv6.ignore-auto-dns connection show "$profile" || true)
  previous_ignore4=${previous_ignore4:-no}
  previous_ignore6=${previous_ignore6:-no}

  ignore4=no
  [[ -n "$v4" ]] && ignore4=yes
  ignore6=no
  [[ -n "$v6" ]] && ignore6=yes

  if [[ "$previous4" == "$v4" && "$previous6" == "$v6" ]] &&
    [[ "$previous_ignore4" == "$ignore4" && "$previous_ignore6" == "$ignore6" ]]; then
    exit 0
  fi

  restore() {
    "$nmcli" connection modify "$profile" \
      ipv4.dns "$previous4" \
      ipv4.ignore-auto-dns "$previous_ignore4" \
      ipv6.dns "$previous6" \
      ipv6.ignore-auto-dns "$previous_ignore6" >/dev/null 2>&1 || true
    "$nmcli" connection up "$profile" >/dev/null 2>&1 || true
  }

  if ! "$nmcli" connection modify "$profile" \
    ipv4.dns "$v4" \
    ipv4.ignore-auto-dns "$ignore4" \
    ipv6.dns "$v6" \
    ipv6.ignore-auto-dns "$ignore6" >/dev/null; then
    restore
    echo "wifi-dns: could not change DNS; reverted to the previous settings" >&2
    exit 1
  fi

  if ! "$nmcli" connection up "$profile" >/dev/null 2>&1; then
    restore
    echo "wifi-dns: could not reconnect with the new DNS; reverted to the previous settings" >&2
    exit 1
  fi
}

case "${1:-}" in
  "") print_status ;;
  set)
    [[ $# -eq 3 ]] || {
      echo "usage: wifi-dns set <ipv4> <ipv6>" >&2
      exit 2
    }
    set_dns "$2" "$3"
    ;;
  *)
    echo "usage: wifi-dns [set <ipv4> <ipv6>]" >&2
    exit 2
    ;;
esac
