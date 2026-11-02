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

band_from_nm() {
  case "$1" in
    bg) echo "2.4" ;;
    a) echo "5" ;;
    6GHz) echo "6" ;;
    *) echo "auto" ;;
  esac
}

band_to_nm() {
  case "$1" in
    2.4) echo "bg" ;;
    5) echo "a" ;;
    6) echo "6GHz" ;;
    *) return 1 ;;
  esac
}

band_for_freq() {
  local mhz=${1%%[!0-9]*}
  [[ -n "$mhz" ]] || return 1

  if ((mhz >= 2400 && mhz < 2500)); then
    echo "2.4"
  elif ((mhz >= 4900 && mhz < 5925)); then
    echo "5"
  elif ((mhz >= 5925 && mhz < 7125)); then
    echo "6"
  else
    return 1
  fi
}

read_active() {
  local device="$1"
  local row

  row=$("$nmcli" -t -e no -f IN-USE,FREQ,SSID dev wifi list ifname "$device" --rescan no 2>/dev/null |
    awk -F: '$1 == "*" { print; exit }')
  [[ -n "$row" ]] || return 1

  freq=${row#*:}
  freq=${freq%%:*}
  ssid=${row#*:*:}
}

selected_band() {
  band_from_nm "$(nm_get 802-11-wireless.band connection show "$1")"
}

available_bands() {
  local device="$1"
  local ssid="$2"
  local current="$3"

  {
    [[ -n "$current" ]] && echo "$current"

    nm_get FREQ,SSID dev wifi list ifname "$device" --rescan no |
      want="$ssid" awk -F: '
        BEGIN { want = ENVIRON["want"] }
        {
          name = $2
          for (i = 3; i <= NF; i++) name = name ":" $i
          if (name == want) print $1
        }' |
      while read -r freq; do
        band_for_freq "$freq" || true
      done
  } | sort -u -g | tr '\n' ' ' | sed 's/ $//'
}

print_status() {
  local device profile band available

  device=$(wifi_device)
  [[ -n "$device" ]] || return 0

  read_active "$device" || return 0
  [[ -n "$ssid" ]] || return 0

  band=$(band_for_freq "$freq" || true)
  available=$(available_bands "$device" "$ssid" "$band")
  profile=$(wifi_profile "$device")

  printf 'band\t%s\n' "$band"
  printf 'available\t%s\n' "$available"
  if [[ -n "$profile" ]]; then
    printf 'selected\t%s\n' "$(selected_band "$profile")"
  fi
}

set_band() {
  local target="$1"
  local device profile previous desired

  device=$(wifi_device)
  [[ -n "$device" ]] || {
    echo "wifi-band: no connected Wi-Fi device" >&2
    exit 1
  }

  profile=$(wifi_profile "$device")
  [[ -n "$profile" ]] || {
    echo "wifi-band: no active Wi-Fi profile" >&2
    exit 1
  }

  if [[ "$target" == "auto" ]]; then
    desired=""
  else
    read_active "$device" || {
      echo "wifi-band: could not read the active link" >&2
      exit 1
    }

    if [[ " $(available_bands "$device" "$ssid" "$(band_for_freq "$freq" || true)") " != *" $target "* ]]; then
      echo "wifi-band: ${target}GHz is not available on this network" >&2
      exit 1
    fi

    desired=$(band_to_nm "$target") || {
      echo "wifi-band: invalid band $target" >&2
      exit 1
    }
  fi

  previous=$(nm_get 802-11-wireless.band connection show "$profile")
  [[ "$previous" == "$desired" ]] && exit 0

  "$nmcli" connection modify "$profile" 802-11-wireless.band "$desired" >/dev/null

  if ! "$nmcli" connection up "$profile" >/dev/null 2>&1; then
    "$nmcli" connection modify "$profile" 802-11-wireless.band "$previous" >/dev/null
    "$nmcli" connection up "$profile" >/dev/null 2>&1 || true
    echo "wifi-band: could not connect on ${target}; reverted to the previous band" >&2
    exit 1
  fi
}

case "${1:-}" in
  "") print_status ;;
  auto | 2.4 | 5 | 6) set_band "$1" ;;
  *)
    echo "usage: wifi-band [auto|2.4|5|6]" >&2
    exit 2
    ;;
esac
