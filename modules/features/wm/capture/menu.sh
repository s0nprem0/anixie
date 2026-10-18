#!/bin/bash
# The whole capture family in one list.
#
#   capture-menu
#
# Every entry is a command this shell already has, so the menu is a way to find
# them rather than a second copy of them. Nothing here does any capturing itself.
#
# It is opened from a bind that enters the picker submap, and it runs its choice in
# the foreground, so the submap is still up when that choice opens the picker —
# Return, Tab and the arrows work from here exactly as they do from the single-key
# binds.

set -uo pipefail

fuzzel="@FUZZEL@"
record="@RECORD@"

# Asked of `record` rather than read out of its pid file here, so the menu and the
# toggle agree on what "recording" means — including the case where the pid file
# has gone stale and a recorder is still running.
recording() {
  "$record" --status
}

menu() {
  cat <<'ENTRIES'
Screenshot — region
Screenshot — window
Screenshot — fullscreen
Screenshot — to clipboard
Annotate a screenshot
Extract text from a region
Scan a QR code
Pick a colour
Transcode a picture or video
Screen record
Screen record — no audio
Screen record — desktop audio
Screen record — desktop and microphone
ENTRIES

  if recording; then
    printf 'Stop screen recording\n'
  fi
}

choice=$(menu | "$fuzzel" --dmenu --prompt='capture  ' --width 36) || exit 0
[ -n "$choice" ] || exit 0

# `exec` for everything that opens the picker or a window of its own: the bind that
# opened this menu waits on it and resets the submap afterwards, and an exec keeps
# that wait meaningful rather than returning the moment this script ends.
case "$choice" in
  "Screenshot — region") exec shot region ;;
  "Screenshot — window") exec shot windows ;;
  "Screenshot — fullscreen") exec shot fullscreen ;;
  "Screenshot — to clipboard") exec shot smart copy ;;
  "Annotate a screenshot") exec shot smart annotate ;;
  "Extract text from a region") exec capture-text ;;
  "Scan a QR code") exec capture-qr ;;
  "Pick a colour") exec hyprpicker -a ;;
  "Transcode a picture or video") exec transcode ;;
  "Screen record") exec record ;;
  "Screen record — no audio") exec record --audio=none ;;
  "Screen record — desktop audio") exec record --audio=desktop ;;
  "Screen record — desktop and microphone") exec record --audio=desktop+mic ;;
  "Stop screen recording") exec record --stop ;;
  *) exit 1 ;;
esac
