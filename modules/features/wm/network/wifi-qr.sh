#!/bin/sh
# The Wi-Fi network you're on, as a QR code a phone can scan to join.
#
#   wifi-qr          write the code and print the file it was written to
#
# The QR carries the network's password in the clear, so it is written to a state
# file rather than shown on demand by anything, and the panel that displays it
# only draws it while a toggle in that panel is on.
#
# `nmcli --show-secrets` reads the pre-shared key of the active connection. That
# is the only place the password is stored in readable form, and asking nmcli is
# asking the network manager that owns the connection rather than parsing its
# connection files by hand.
set -eu

nmcli="@NMCLI@"
qrencode="@QRENCODE@"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/anixie"

out="$state_dir/wifi-qr.png"

mkdir -p "$state_dir"

ssid=$("$nmcli" -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')
[ -n "$ssid" ] || { echo "wifi-qr: not connected to Wi-Fi" >&2; exit 1; }

# The connection's own name, which is not always the SSID — a hidden network has
# no SSID at all and is joined by connection name.
connection=$("$nmcli" -g GENERAL.CONNECTION dev show "$ssid" 2>/dev/null | head -1)
[ -n "$connection" ] || connection="$ssid"

psk=$("$nmcli" --show-secrets -g 802-11-wireless-security.psk con show "$connection" 2>/dev/null | head -1)
[ -n "$psk" ] || { echo "wifi-qr: no saved password for $ssid (open network?)" >&2; exit 1; }

# The WIFI: URI every phone's scanner understands. Escaped so a password with a
# backslash, a semicolon or a quote in it does not produce a code that joins a
# different network than the one named.
payload="WIFI:T:WPA;S:$(printf '%s' "$ssid" | sed -e 's/[\\;,":]/\\\\&/g');P:$(printf '%s' "$psk" | sed -e 's/[\\;,":]/\\\\&/g');;"

"$qrencode" -t PNG -o "$out" -s 6 -m 1 "$payload"

printf '%s\n' "$out"