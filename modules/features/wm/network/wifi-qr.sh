#!/bin/sh
# The Wi-Fi network you're on, as a QR code a phone can scan to join.
#
#   wifi-qr              write the code and print the file it was written to
#   wifi-qr --password   print the active network's password
#
# The QR may carry the network's password in the clear, so the file is written
# with the password in mind: a 0700 directory, a 0600 file, and the panel that
# displays it deletes it when the toggle goes off.
#
# `nmcli --show-secrets` reads the key of the active connection. That is the
# only place the password is stored in readable form, and asking nmcli is
# asking the network manager that owns the connection rather than parsing its
# connection files by hand.
set -eu

mode=qr
case "${1:-}" in
  "") ;;
  --password) mode=password ;;
  *)
    echo "usage: wifi-qr [--password]" >&2
    exit 2
    ;;
esac

# Everything below can contain the key; keep it out of reach of other users.
umask 077

nmcli="@NMCLI@"
qrencode="@QRENCODE@"

if [ -n "${XDG_STATE_HOME:-}" ]; then
  state_home=$XDG_STATE_HOME
else
  [ -n "${HOME:-}" ] || { echo "wifi-qr: HOME is not set" >&2; exit 1; }
  state_home=$HOME/.local/state
fi

state_dir="$state_home/anixie"
out="$state_dir/wifi-qr.png"

# A directory that already exists is left with its old mode by mkdir -p; this
# sets it, and 0700 is also what the umask above gives a new one.
install -d -m 700 "$state_dir"

# `-g` is terse output, so it escapes `:` and `\`. Values read back with it are
# escaped again unless they are decoded first — and an escaped profile name is
# not the name `nmcli con show` accepts.
unescape() { sed -e 's/\\\([\\:]\)/\1/g'; }

# The WIFI: URI escaping, the other direction.
escape() { sed -e 's/[\\;,":]/\\&/g'; }

# The connection is found through the device, not by treating the SSID as one:
# `nmcli dev show <ssid>` only works when the SSID happens to be an interface
# name. GENERAL.CONNECTION is the profile, and the profile is what the con
# verbs take.
iface=$("$nmcli" -t -f DEVICE,TYPE device status 2>/dev/null |
  awk -F: '$2 == "wifi" { print $1; exit }')
[ -n "$iface" ] || { echo "wifi-qr: no Wi-Fi device" >&2; exit 1; }

connection=$("$nmcli" -g GENERAL.CONNECTION device show "$iface" 2>/dev/null | head -1 | unescape)
[ -n "$connection" ] || { echo "wifi-qr: not connected to Wi-Fi" >&2; exit 1; }

ssid=$("$nmcli" -g 802-11-wireless.ssid con show "$connection" 2>/dev/null | head -1 | unescape)
[ -n "$ssid" ] || ssid=$connection

keymgmt=$("$nmcli" -g 802-11-wireless-security.key-mgmt con show "$connection" 2>/dev/null | head -1 | unescape)
psk=$("$nmcli" --show-secrets -g 802-11-wireless-security.psk con show "$connection" 2>/dev/null | head -1 | unescape)
wep=$("$nmcli" --show-secrets -g 802-11-wireless-security.wep-key0 con show "$connection" 2>/dev/null | head -1 | unescape)

case "$keymgmt" in
  wpa-eap | ieee8021x)
    echo "wifi-qr: 802.1X networks cannot be shared with a QR code" >&2
    exit 1
    ;;
esac

if [ -n "$psk" ]; then
  type=WPA
  secret=$psk
elif [ -n "$wep" ]; then
  type=WEP
  secret=$wep
elif [ -z "$keymgmt" ] || [ "$keymgmt" = "none" ]; then
  type=nopass
  secret=""
else
  echo "wifi-qr: no shareable password for $ssid ($keymgmt)" >&2
  exit 1
fi

if [ "$mode" = password ]; then
  [ -n "$secret" ] || { echo "wifi-qr: this network has no password" >&2; exit 1; }
  printf '%s\n' "$secret"
  exit 0
fi

# The WIFI: URI every phone's scanner understands, escaped so a password with a
# backslash, a semicolon or a quote in it does not produce a code that joins a
# different network than the one named.
ssid_esc=$(printf '%s' "$ssid" | escape)

if [ "$type" = "nopass" ]; then
  payload="WIFI:T:nopass;S:$ssid_esc;;"
else
  payload="WIFI:T:$type;S:$ssid_esc;P:$(printf '%s' "$secret" | escape);;"
fi

# Remove the old file first: writing over it keeps its mode, and a code written
# before this script set a umask would stay world-readable.
rm -f "$out"
"$qrencode" -t PNG -o "$out" -s 6 -m 1 "$payload"
chmod 600 "$out"

printf '%s\n' "$out"
