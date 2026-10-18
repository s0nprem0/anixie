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
#   annotate  open it in satty, which starts in crop mode, and save the result
#   -- CMD    run CMD with the captured file, instead of saving or copying
#
#   shot region annotate             drag a region, then crop and mark it up
#   shot region -- satty            hand the capture to a viewer
#   shot windows copy                pick a window, copy it, save nothing
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
    annotate)
      dest="annotate"
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
  mkdir -p "$shot_dir"
  set -- "$@" -o "$shot_dir"
fi

# Annotation opens the capture in satty, which is written for Wayland and starts
# in crop mode. swappy was the tool here before and drew nothing: it is an X11-era
# GTK application, and run under XWayland its window never appeared.
#
# satty is told both ends explicitly rather than being handed the capture as a
# trailing argument, because it takes the file as a named option and has no
# positional form.
if [ "$dest" = "annotate" ]; then
  raw="$shot_dir/.annotate-$(date +%Y%m%d-%H%M%S)-$$.png"
  @HYPRSHOT@ "$@" -f "$(basename "$raw")" >/dev/null 2>&1 || true

  if [ ! -s "$raw" ]; then
    printf 'shot: nothing was captured (the selection may have been cancelled)\n' >&2
    exit 1
  fi

  @SATTY@ --filename "$raw" --output-filename "$shot_dir/$(date +%Y-%m-%d_%H-%M-%S).png" --initial-tool crop
  status=$?
  rm -f "$raw"
  exit "$status"
fi

# hyprshot 1.3.0 always exits 1, having written the file perfectly well: its
# wait loop ends with a bare `exit`, which takes the status of the `pkill` before
# it, and `pkill` returns 1 when there was nothing left to kill. So its status is
# no use either way, and the file is asked about instead.
#
# Naming the file here also drops the `_hyprshot` suffix its own default appends,
# and puts a dash in the time so a timestamp sorts the way it reads.
if [ "$dest" = "copy" ]; then
  @HYPRSHOT@ "$@" || true
  exit 0
fi

# A command after `--` is run with the captured file appended. hyprshot's own
# status is not the command's, so it is dropped here and the command's status is
# what leaves.
if [ -n "$post" ]; then
  file="$shot_dir/$(date +%Y-%m-%d_%H-%M-%S).png"
  @HYPRSHOT@ "$@" -f "$(basename "$file")" >/dev/null 2>&1 || true
  if [ -s "$file" ]; then
    # shellcheck disable=SC2086
    exec $post "$file"
  fi
  printf 'shot: nothing was captured (the selection may have been cancelled)\n' >&2
  exit 1
fi

file="$shot_dir/$(date +%Y-%m-%d_%H-%M-%S).png"
@HYPRSHOT@ "$@" -f "$(basename "$file")" || true

if [ -s "$file" ]; then
  printf 'Saved %s\n' "$file"
  exit 0
fi

printf 'shot: nothing was captured (the selection may have been cancelled)\n' >&2
exit 1