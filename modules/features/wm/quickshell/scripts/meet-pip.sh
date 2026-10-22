#!/bin/sh
# Google Meet picture-in-picture for the current Hyprland session.
#
#   meet-pip.sh status    print "1<TAB>title" when a Meet window exists, else 0
#   meet-pip.sh toggle    float, pin, resize and move a Meet window, or restore
#
# A browser cannot hand a video stream to a QML surface, so this is the local
# equivalent: keep the Meet window itself floating and pinned in a corner. The
# geometry it had before is saved next to the runtime socket and restored on the
# next toggle. There is no daemon and no polling; the widget asks for status.

set -eu

hyprctl="${HYPRCTL:-hyprctl}"
jq="${JQ:-jq}"
mode="${1:-toggle}"
match="Meet|meet\\.google\\.com"

clients=$("$hyprctl" clients -j 2>/dev/null || printf '[]')
entry=$(
  printf '%s' "$clients" \
    | "$jq" -r --arg re "$match" '
        [.[] | select(
          (((.title // "") + " " + (.initialTitle // "") + " " + (.class // "")) | test($re; "i"))
        )][0] // empty
        | [.address, .title] | @tsv
      ' 2>/dev/null || true
)

tab=$(printf '\t')
address=""
title=""
if [ -n "$entry" ]; then
  address=${entry%%"$tab"*}
  title=${entry#*"$tab"}
fi

if [ "$mode" = "status" ]; then
  if [ -n "$address" ]; then
    printf '1\t%s\n' "$title"
  else
    printf '0\n'
  fi
  exit 0
fi

if [ "$address" = "" ]; then
  exit 1
fi

runtime="${XDG_RUNTIME_DIR:-/tmp}"
state_dir="$runtime/anixie-meet-pip"
state_file="$state_dir/$address"
mkdir -p "$state_dir"
chmod 700 "$state_dir"

client=$(
  printf '%s' "$clients" \
    | "$jq" -c --arg a "$address" '.[] | select(.address == $a)' 2>/dev/null
)

restore() {
  saved=$1
  saved_x=$("$jq" -r '.x' "$saved")
  saved_y=$("$jq" -r '.y' "$saved")
  saved_w=$("$jq" -r '.width' "$saved")
  saved_h=$("$jq" -r '.height' "$saved")
  saved_float=$("$jq" -r '.floating' "$saved")
  saved_pin=$("$jq" -r '.pinned' "$saved")

  "$hyprctl" dispatch focuswindow "address:$address" >/dev/null

  current=$("$hyprctl" clients -j 2>/dev/null | "$jq" -c --arg a "$address" '.[] | select(.address == $a)' 2>/dev/null || true)
  if [ -n "$current" ]; then
    current_float=$(printf '%s' "$current" | "$jq" -r '.floating')
    current_pin=$(printf '%s' "$current" | "$jq" -r '.pinned')
    if [ "$saved_float" != "$current_float" ]; then
      "$hyprctl" dispatch togglefloating "address:$address" >/dev/null
    fi
    if [ "$saved_pin" != "$current_pin" ]; then
      "$hyprctl" dispatch pin "address:$address" >/dev/null
    fi
  fi

  "$hyprctl" dispatch resizeactive exact "$saved_w" "$saved_h" >/dev/null
  "$hyprctl" dispatch moveactive exact "$saved_x" "$saved_y" >/dev/null
}

# A stale state file is from a window that has since closed or been restarted;
# drop it rather than restoring geometry onto an unrelated window.
if [ -f "$state_file" ]; then
  if [ "$("$jq" -r '.address // empty' "$state_file" 2>/dev/null || true)" = "$address" ]; then
    restore "$state_file"
    rm -f "$state_file"
    exit 0
  fi
  rm -f "$state_file"
fi

x=$(printf '%s' "$client" | "$jq" -r '.at[0] | floor')
y=$(printf '%s' "$client" | "$jq" -r '.at[1] | floor')
w=$(printf '%s' "$client" | "$jq" -r '.size[0] | floor')
h=$(printf '%s' "$client" | "$jq" -r '.size[1] | floor')
floating=$(printf '%s' "$client" | "$jq" -r '.floating')
pinned=$(printf '%s' "$client" | "$jq" -r '.pinned')
monitor=$(printf '%s' "$client" | "$jq" -r '.monitor')

"$jq" -n \
  --arg address "$address" \
  --argjson x "$x" \
  --argjson y "$y" \
  --argjson width "$w" \
  --argjson height "$h" \
  --argjson floating "$floating" \
  --argjson pinned "$pinned" \
  '{address: $address, x: $x, y: $y, width: $width, height: $height,
    floating: $floating, pinned: $pinned}' >"$state_file"

mon=$(
  "$hyprctl" monitors -j 2>/dev/null \
    | "$jq" -c --argjson id "$monitor" '.[] | select(.id == $id)' 2>/dev/null || true
)
if [ -z "$mon" ] || [ "$mon" = "null" ]; then
  mon=$("$hyprctl" monitors -j 2>/dev/null | "$jq" -c '.[] | select(.focused == true)' 2>/dev/null || true)
fi
[ -n "$mon" ] && [ "$mon" != "null" ] || mon='{}'

mx=$(printf '%s' "$mon" | "$jq" -r '.x // 0')
my=$(printf '%s' "$mon" | "$jq" -r '.y // 0')
mw=$(printf '%s' "$mon" | "$jq" -r '.width // 1920')
mh=$(printf '%s' "$mon" | "$jq" -r '.height // 1080')

pip_w=480
pip_h=270
margin=16
pip_x=$((mx + mw - pip_w - margin))
pip_y=$((my + mh - pip_h - margin))

"$hyprctl" dispatch focuswindow "address:$address" >/dev/null
if [ "$floating" != "true" ]; then
  "$hyprctl" dispatch togglefloating "address:$address" >/dev/null
fi
if [ "$pinned" != "true" ]; then
  "$hyprctl" dispatch pin "address:$address" >/dev/null
fi
"$hyprctl" dispatch resizeactive exact "$pip_w" "$pip_h" >/dev/null
"$hyprctl" dispatch moveactive exact "$pip_x" "$pip_y" >/dev/null
