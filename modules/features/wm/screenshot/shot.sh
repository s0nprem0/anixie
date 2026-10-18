#!/bin/sh
# Screenshots, with the modes the reference shell uses and none of its branding.
#
#   shot                      the same as `shot smart save`
#   shot smart                active window if there is one, else the whole screen
#   shot windows              pick a window from the screen
#   shot region               drag a region
#   shot fullscreen           the whole screen
#   shot window               the window with focus, without asking
#
# Destination:
#
#   save      write a PNG into $SHOT_DIR (default ~/Pictures/Screenshots)
#   copy      put it on the clipboard and write nothing
#   -- CMD    run CMD with the captured file, instead of saving or copying
#
#   shot region -- satty              hand the capture to a viewer
#   shot windows copy                 pick a window, copy it, save nothing
#
# `scroll` is not a mode here. Capturing a window taller than the screen needs a
# composition of the screen over time that neither grim nor hyprshot can do —
# grim only reads what is currently on the display — so it is left out rather
# than quietly capturing the wrong thing.

set -eu

shot_dir="${SHOT_DIR:-$HOME/Pictures/Screenshots}"

mode="smart"
dest="save"
post=""

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

# Parsed with `shift` rather than `for arg in "$@"`, because the hyprshot
# arguments are built below with `set --` — and a `for` loop iterates the list it
# captured at the start, so `set --` would leave the two disagreeing about what
# "$@" holds. That is how `-- CMD` ended up forwarded as `-- -- CMD`.
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    smart | windows | region | fullscreen | window)
      mode="$1"
      ;;
    save | copy)
      dest="$1"
      ;;
    scroll)
      printf 'shot: "scroll" is not supported — it needs a capture that extends past the screen.\n' >&2
      printf 'Use "shot windows" to pick a window, or "shot region" to drag one.\n' >&2
      exit 2
      ;;
    --)
      shift
      # Everything left is the command, with its own spaces preserved.
      post="$*"
      break
      ;;
    *)
      printf 'shot: unknown argument "%s" (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

# hyprshot only knows these. `windows` is its interactive window picker, which is
# what the reference shell's `windows` mode means.
#
# `active` comes first on the non-interactive modes: hyprshot reads it as "the one
# already in focus, do not ask", and on its own `-m output` is a picker over the
# monitors, so a bare `-m output` would sit waiting for a click to capture the
# screen the user is already looking at.
case "$mode" in
  fullscreen) set -- -m active -m output ;;
  windows) set -- -m window ;;
  region) set -- -m region ;;
  window) set -- -m active -m window ;;
  smart)
    if hyprctl activewindow -j >/dev/null 2>&1; then
      set -- -m active -m window
    else
      set -- -m active -m output
    fi
    ;;
esac

# Copying and saving are mutually exclusive in hyprshot, and it writes into its
# own directory otherwise, so the folder is stated either way to keep every route
# landing in the same place.
if [ "$dest" = "copy" ]; then
  set -- "$@" --clipboard-only
else
  set -- "$@" -o "$shot_dir"
  mkdir -p "$shot_dir"
fi

# A command after `--` is run with the captured file appended, which is how
# annotation and viewers are reached. Without one, the capture is saved (or
# copied) as-is and hyprshot says so with its own notification.
if [ -n "$post" ]; then
  # shellcheck disable=SC2086
  exec @HYPRSHOT@ "$@" -- $post
fi

exec @HYPRSHOT@ "$@"