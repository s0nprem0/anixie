#!/bin/sh
# Screenshots, with the modes the reference shell uses and none of its branding.
#
#   shot                      pick a region, the way the reference shell's `smart`
#   shot region               drag a region, no snapping
#   shot windows              snap to a window or monitor
#   shot fullscreen           the focused monitor, no interaction
#   shot window               the window with focus, no picker
#
# Destination:
#
#   save      write a PNG into $SHOT_DIR (default ~/Pictures/Screenshots)
#   copy      put it on the clipboard and write nothing
#   annotate  open it in satty, which starts in crop mode, and save the result
#   -- CMD    run CMD with the captured file
#
#   shot windows copy         snap to a window, copy it, save nothing
#   shot region -- satty      hand the capture to a viewer
#
# While the picker is open it can also be driven from the keyboard: RETURN takes
# the window under the pointer and CTRL+RETURN the monitor, TAB cycles the windows
# and CTRL+TAB goes back, and the arrows move between them. Those keys are bound
# to `shot-pick` against slurp's layer in features/wm/hyprland/settings.nix.

set -eu

shot_dir="${SHOT_DIR:-$HOME/Pictures/Screenshots}"

mode="smart"
dest="save"
post=""

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    smart | region | windows | fullscreen | window)
      mode="$1"
      ;;
    save | copy | annotate)
      dest="$1"
      ;;
    scroll)
      printf 'shot: "scroll" is not supported — it needs a capture that extends past the screen.\n' >&2
      printf 'Use "shot windows" to pick a window, or "shot region" to drag one.\n' >&2
      exit 2
      ;;
    --)
      shift
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

# `window` is the one mode the picker has no equivalent of: the window that
# already has focus, with no interaction at all. It is read from the compositor
# rather than offered by the picker, because asking someone to click the window
# they are already looking at is a question with one answer.
if [ "$mode" = "window" ]; then
  geometry=$(@HYPRCTL@ clients -j | @JQ@ -r --arg ws "$(@HYPRCTL@ activeworkspace -j | @JQ@ -r '.id')" '
    [.[] | select(.workspace.id == ($ws | tonumber) and .hidden != true)] | last
    | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
else
  geometry=$(@SHOT_PICK@ "$mode") || exit 1
fi

[ -n "$geometry" ] || exit 1

mkdir -p "$shot_dir"

# Named here rather than left to a tool's default, so the timestamp reads the way
# it sorts and nothing appends a tool name to it.
#
# Two captures inside the same second would otherwise land on the same name, and
# the second would quietly replace the first — which is the one moment you most
# want both copies of.
stamp=$(date +%Y-%m-%d_%H-%M-%S)
file="$shot_dir/$stamp.png"
suffix=1
while [ -e "$file" ]; do
  file="$shot_dir/$stamp-$suffix.png"
  suffix=$((suffix + 1))
done

@GRIM@ -g "$geometry" "$file"

if [ ! -s "$file" ]; then
  printf 'shot: nothing was captured\n' >&2
  exit 1
fi

case "$dest" in
  copy)
    @WL_COPY@ --type image/png <"$file"
    rm -f "$file"
    ;;
  annotate)
    @SATTY@ --filename "$file" --output-filename "$shot_dir/$stamp-annotated.png" --initial-tool crop
    status=$?
    rm -f "$file"
    exit "$status"
    ;;
  save)
    if [ -n "$post" ]; then
      # shellcheck disable=SC2086
      exec $post "$file"
    fi
    printf 'Saved %s\n' "$file"
    ;;
esac