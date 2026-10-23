#!/bin/sh
# Screenshots, with the modes the reference shell uses and none of its branding.
#
#   shot                      pick a region, the way the reference shell's `smart`
#   shot region               drag a region, no snapping
#   shot windows              snap to a window or monitor
#   shot fullscreen           the focused monitor, no interaction
#   shot window               the window with focus, no picker
#   shot scroll               page through a scrollable window and stitch the frames
#
# Destination:
#
#   preview   save it, copy it, and show it for ten seconds — the default
#   save      write a PNG into $SHOT_DIR (default ~/Pictures/Screenshots) and stop
#   copy      put it on the clipboard and write nothing
#   annotate  open it in satty, which starts in crop mode, and save the result
#   redact    open satty with the blur tool selected, for covering secrets
#   text      open satty with the text tool selected, for adding a caption
#
# The destinations are not combined; a capture goes to one place. `preview` is the
# default because a screenshot is usually taken to be pasted somewhere, and having
# it on the clipboard already is the difference between one step and three. `save`
# is the one to ask for when a script wants the file and nothing else — no
# clipboard, no window.
#
#   shot windows copy         snap to a window, copy it, save nothing
#   shot region annotate      drag a region, then annotate it
#   shot fullscreen save      the monitor, written out, nothing else
#   shot scroll save          page through a page and save the stitched image
#
# Scrolling capture is automatic and keyboard-driven: select the region, then
# leave the scrollable window focused. It sends Page Down between frames and
# stops when the content stops changing, when SCROLL_FRAMES is reached, or when
# the stitched image would exceed SCROLL_MAX_HEIGHT pixels. SCROLL_FRAMES,
# SCROLL_PRESSES, SCROLL_KEY_DELAY and SCROLL_SETTLE tune it. It works with any
# app that scrolls on Page Down; a terminal that uses Page Down for history
# scrolls too, which is often exactly what is wanted.
#
# `-- CMD` hands the saved file to CMD instead of printing where it landed. It
# goes with `save` only, because the file CMD is given has to be one that stays
# put:
#
#   shot region save -- satty  hand the saved capture to a viewer
#
# While the picker is open it can also be driven from the keyboard: RETURN takes
# the window under the pointer and SUPER+RETURN the monitor, TAB cycles the windows
# and SHIFT+TAB goes back, and the arrows move between them. Those keys are bound
# to `shot-pick` against the picker's submap in
# features/wm/hyprland/config/75-rules.lua.

set -eu

shot_dir="${SHOT_DIR:-$HOME/Pictures/Screenshots}"

mode="smart"
dest="preview"
post=""

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    smart | region | windows | fullscreen | window)
      mode="$1"
      ;;
    save | copy | annotate | preview | redact | text)
      dest="$1"
      ;;
    scroll)
      mode="scroll"
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

# `-- CMD` runs against a file that is kept, so it cannot be combined with a
# destination that keeps nothing (copy) or keeps a different file (annotate).
if [ -n "$post" ] && [ "$dest" != "save" ]; then
  printf 'shot: -- CMD cannot be combined with "%s"\n' "$dest" >&2
  exit 2
fi

# Scrolling capture settings. Page Down is the key every scrollable surface
# understands; the settle delay is longer than a frame so the compositor has
# drawn the new position before grim reads it.
scroll_frames="${SCROLL_FRAMES:-16}"
scroll_presses="${SCROLL_PRESSES:-1}"
scroll_key_delay="${SCROLL_KEY_DELAY:-0.08}"
scroll_settle="${SCROLL_SETTLE:-0.45}"
scroll_max_height="${SCROLL_MAX_HEIGHT:-24000}"

# The freeze's pid is written by the picker, which exits as soon as a selection is
# made and leaves the freeze for whoever asked for it. Taking it down is therefore
# this process's job.
#
# Set up *before* the picker runs, not after. A cancelled picker — Escape, or a
# click outside the selection — exits this script on the line below, and a trap
# installed afterwards would never be reached: the pid file would be left behind
# for the next capture to read, and the freeze would be left on screen.
#
# One trap covers both cleanups — the freeze, and the scratch file `copy` and
# `annotate` grim into — because they are set at different points and a second
# `trap` would replace the first.
#
# The scratch file is tracked in its own variable rather than by testing
# `captured`, because `captured` is also the saved capture in the destinations that
# keep it. Removing that on exit would delete the screenshot on the way out — which
# is exactly what happened when the two shared one variable.
freeze_pid_file="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie/anixie-pick-freeze.pid"
captured=""
scratch=""
scroll_tmp=""

release_freeze() {
  [ -f "$freeze_pid_file" ] || return 0
  kill "$(cat "$freeze_pid_file" 2>/dev/null)" 2>/dev/null
  rm -f "$freeze_pid_file"
}

# The explicit `return 0` is not decoration. Under `set -e`, a trap whose last
# command is a failing `&&` list leaves that failure as the script's exit status —
# so a run that saved its screenshot perfectly well exited 1 whenever there was no
# scratch file to remove, which is every run that keeps its capture. Ending on a
# success is what stops the cleanup from being mistaken for a failure.
cleanup() {
  release_freeze
  [ -n "$scratch" ] && rm -f "$scratch"
  [ -n "$scroll_tmp" ] && rm -rf "$scroll_tmp"
  return 0
}

trap cleanup EXIT HUP INT TERM

# `window` is the one mode the picker has no equivalent of: the window that
# already has focus, with no interaction at all. It is read from the compositor
# rather than offered by the picker, because asking someone to click the window
# they are already looking at is a question with one answer.
#
# `activewindow` is the focused window. `clients | last` is not a substitute: the
# client list is ordered by creation, not focus, so `last` is the newest window on
# the workspace and `shot window` would capture something other than the one in
# front of you whenever a newer window sits behind it.
if [ "$mode" = "window" ]; then
  geometry=$(@HYPRCTL@ activewindow -j | @JQ@ -r '
    if .at == null or .size == null then empty
    else "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" end')
  if [ -z "$geometry" ]; then
    printf 'shot: no focused window to capture\n' >&2
    exit 1
  fi
else
  # --keep-freeze so the capture sees the frame that was aimed at rather than
  # whatever moved while the pointer was being placed. The picker writes the
  # freeze's pid to a file and leaves it running; grim reads the screen, and the
  # freeze is released below, once there is nothing left that needs it.
  picker_mode="$mode"
  [ "$mode" = "scroll" ] && picker_mode=region
  geometry=$(@SHOT_PICK@ "$picker_mode" --keep-freeze) || exit 1
fi

[ -n "$geometry" ] || exit 1

# The first free name for a given stem. Two captures inside the same second would
# otherwise land on the same name and the second would quietly replace the first —
# which is the one moment you most want both copies of.
unique_path() {
  candidate="$shot_dir/$1.$2"
  suffix=1
  while [ -e "$candidate" ]; do
    candidate="$shot_dir/$1-$suffix.$2"
    suffix=$((suffix + 1))
  done
  printf '%s' "$candidate"
}

# Timestamped here rather than left to a tool's default, so the name reads the way
# it sorts and nothing appends a tool name to it.
stamp=$(date +%Y-%m-%d_%H-%M-%S)

# ---- scrolling capture ----
#
# Page Down is deliberately used instead of a mouse wheel: it needs no pointer
# position and every toolkit understands it. The overlap between two frames is
# found by taking a strip from the previous frame, well above its bottom edge so
# a sticky footer cannot anchor the match, and searching for it in the new one.
# A normalized RMSE below 0.08 is a match; anything else is treated as "the page
# moved by a whole viewport" and the frame is appended whole, which at worst
# repeats the one line that page-down leaves behind.

# Print the number of pixels the previous frame and the current frame share, or
# fail when there is no usable match. The search runs on a quarter-size copy:
# the answer is a y offset, and a full-resolution subimage search over a 1080p
# frame is slow enough to be felt between every page.
scroll_overlap() {
  previous="$1"
  current="$2"

  previous_size=$(@MAGICK@ identify -format '%w %h' "$previous" 2>/dev/null) || return 1
  current_size=$(@MAGICK@ identify -format '%w %h' "$current" 2>/dev/null) || return 1
  set -- $previous_size
  previous_width=$1
  previous_height=$2
  set -- $current_size
  current_width=$1

  [ "$previous_width" -eq "$current_width" ] || return 1
  [ "$previous_height" -gt 0 ] || return 1

  scale=4
  [ "$previous_width" -lt 400 ] && scale=1
  small_width=$((previous_width / scale))
  small_height=$((previous_height / scale))
  [ "$small_width" -gt 0 ] && [ "$small_height" -gt 0 ] || return 1

  strip_height=$((small_height / 8))
  [ "$strip_height" -ge 8 ] || strip_height=8
  [ "$strip_height" -lt "$small_height" ] || return 1
  strip_top=$((small_height * 3 / 5))
  [ $((strip_top + strip_height)) -le "$small_height" ] || strip_top=$((small_height - strip_height))

  small_previous="$scroll_tmp/previous-small.png"
  small_current="$scroll_tmp/current-small.png"
  strip="$scroll_tmp/strip.png"
  @MAGICK@ "$previous" -resize "${small_width}x${small_height}!" "$small_previous" 2>/dev/null || return 1
  @MAGICK@ "$current" -resize "${small_width}x${small_height}!" "$small_current" 2>/dev/null || return 1
  @MAGICK@ "$small_previous" -crop "${small_width}x${strip_height}+0+${strip_top}" +repage "$strip" 2>/dev/null || return 1

  # `compare` exits 1 when the images differ, which is the normal case. Its
  # metric goes to stderr: "1234.5 (0.0123) @ 0,120".
  metric=$(@MAGICK@ compare -metric RMSE -subimage-search "$small_current" "$strip" null: 2>&1 >/dev/null || true)
  threshold=$(printf '%s\n' "$metric" | sed -n 's/.*(\([0-9.][0-9.]*\)).*/\1/p')
  match_y=$(printf '%s\n' "$metric" | sed -n 's/.*@ [0-9-]*,\([0-9-][0-9-]*\).*/\1/p')
  [ -n "$threshold" ] && [ -n "$match_y" ] || return 1
  # 0.08 is generous on purpose: JPEG-ish UI noise and subpixel rendering move
  # the score a little even when the scroll position is exactly right.
  awk -v score="$threshold" 'BEGIN { exit !(score <= 0.08) }' || return 1

  # The strip started at `strip_top` in the previous frame and appears at
  # `match_y` in the current one, so the scroll distance is the difference and
  # everything after it is new.
  scroll_distance=$((strip_top * scale - match_y * scale))
  overlap=$((previous_height - scroll_distance))
  [ "$overlap" -gt 0 ] && [ "$overlap" -lt "$previous_height" ] || return 1
  printf '%s\n' "$overlap"
}

# Append the new part of `frame` to `stitched`, skipping the overlap. A missing
# overlap means "append it whole"; a negative one cannot happen because the
# caller only passes a value that has been checked.
scroll_append() {
  stitched="$1"
  frame="$2"
  overlap="$3"

  size=$(@MAGICK@ identify -format '%w %h' "$frame" 2>/dev/null) || return 1
  set -- $size
  frame_width=$1
  frame_height=$2

  if [ "$overlap" -gt 0 ] && [ "$overlap" -lt "$frame_height" ]; then
    part="$scroll_tmp/part.png"
    @MAGICK@ "$frame" -crop "${frame_width}x$((frame_height - overlap))+0+${overlap}" +repage "$part" 2>/dev/null || return 1
  else
    part="$frame"
  fi

  @MAGICK@ "$stitched" "$part" -append "$scroll_tmp/next.png" 2>/dev/null || return 1
  mv "$scroll_tmp/next.png" "$stitched"
}

# Select once, then page down until the view stops moving. The picker's freeze
# is released before the first scroll so the frames are live; the caller's trap
# still covers the case where no frame was ever captured.
scroll_capture() {
  geometry="$1"
  output="$2"

  release_freeze

  # Page Down goes to whatever has focus, not to the window that was picked.
  # Without a guard, switching windows mid-capture pages an unrelated app and
  # stitches its frames into the result. The address is taken once, before the
  # first key, and checked before every frame; a window that was closed or
  # replaced stops the loop with the frames captured so far instead of
  # scrolling something else.
  scroll_focus=$(@HYPRCTL@ activewindow -j 2>/dev/null | @JQ@ -r '.address // empty' 2>/dev/null || true)

  @NOTIFY_SEND_RAW@ -a capture -u low -t 2500 \
    "Scrolling capture" "Leave the window focused. It stops when the page stops moving." >/dev/null 2>&1 || true

  i=0
  previous=""
  while [ "$i" -lt "$scroll_frames" ]; do
    if [ -n "$scroll_focus" ]; then
      focused=$(@HYPRCTL@ activewindow -j 2>/dev/null | @JQ@ -r '.address // empty' 2>/dev/null || true)
      if [ "$focused" != "$scroll_focus" ]; then
        @NOTIFY_SEND_RAW@ -a capture -u normal -t 4000 \
          "Scrolling capture stopped" "Focus moved to another window. The part captured so far was kept." >/dev/null 2>&1 || true
        break
      fi
    fi

    current="$scroll_tmp/frame-$i.png"
    @GRIM@ -g "$geometry" "$current" 2>/dev/null || break
    [ -s "$current" ] || break

    if [ -z "$previous" ]; then
      cp "$current" "$scroll_tmp/stitched.png"
    else
      unchanged=$(@MAGICK@ compare -metric AE "$previous" "$current" null: 2>&1 >/dev/null || true)
      case "$unchanged" in
        0 | "0 (0)") break ;;
      esac

      if overlap=$(scroll_overlap "$previous" "$current"); then
        scroll_append "$scroll_tmp/stitched.png" "$current" "$overlap" || break
      else
        scroll_append "$scroll_tmp/stitched.png" "$current" 0 || break
      fi

      height=$(@MAGICK@ identify -format '%h' "$scroll_tmp/stitched.png" 2>/dev/null || echo 0)
      [ "$height" -lt "$scroll_max_height" ] || break
    fi

    previous="$current"
    i=$((i + 1))
    [ "$i" -ge "$scroll_frames" ] && break

    key=0
    while [ "$key" -lt "$scroll_presses" ]; do
      @WTYPE@ -k Next 2>/dev/null || break
      sleep "$scroll_key_delay"
      key=$((key + 1))
    done
    sleep "$scroll_settle"
  done

  [ -s "$scroll_tmp/stitched.png" ] || return 1
  cp "$scroll_tmp/stitched.png" "$output"
}

# What was in front when the capture was taken, for the name — the reference names
# its files `screenshot-<time>-<app>.png`, and the app is what makes a directory of
# shots searchable. Lowercased and reduced to dashes, so a class like
# `org.gnome.Nautilus` becomes `org-gnome-nautilus` rather than something with dots
# in it. Absent when nothing is focused, and the name simply has no suffix then.
window_slug=$(
  @HYPRCTL@ activewindow -j 2>/dev/null |
    @JQ@ -r '.class // empty' 2>/dev/null |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' |
    cut -c 1-40
)

# `copy` and `annotate` grim into a temporary file: what they keep is the
# clipboard or satty's output, not the raw capture, and writing the raw capture
# into $SHOT_DIR on the way would leave one behind for nothing.
case "$dest" in
  copy | annotate | redact | text)
    captured=$(mktemp "${TMPDIR:-/tmp}/shot.XXXXXX.png")
    scratch="$captured"
    ;;
  *)
    mkdir -p "$shot_dir"
    captured=$(unique_path "screenshot-$stamp${window_slug:+-$window_slug}" png)
    ;;
esac

# -c includes the cursor, which is what the reference does: a screenshot is often
# taken to show where something is, and the pointer is part of that. The text and
# QR captures deliberately leave it out — a cursor sitting on the text being read
# is one more thing for the reader to work around.
if [ "$mode" = "scroll" ]; then
  scroll_tmp=$(mktemp -d "${TMPDIR:-/tmp}/shot-scroll.XXXXXX")
  if ! scroll_capture "$geometry" "$captured"; then
    printf 'shot: scrolling capture produced nothing\n' >&2
    exit 1
  fi
else
  @GRIM@ -c -g "$geometry" "$captured"
fi

# Down as soon as grim has read the screen. Nothing after this needs the still
# frame, and holding it would leave it over the desktop while the capture is
# written and copied.
release_freeze

if [ ! -s "$captured" ]; then
  printf 'shot: nothing was captured\n' >&2
  exit 1
fi

case "$dest" in
  copy)
    # Only a copy that reached the clipboard is thrown away. A clipboard that
    # could not be written to — no compositor, or another client holding the
    # selection — would otherwise take the capture down with it, so it is saved
    # instead and the path named on stderr.
    if ! @WL_COPY@ --type image/png <"$captured"; then
      mkdir -p "$shot_dir"
      fallback=$(unique_path "screenshot-$stamp${window_slug:+-$window_slug}" png)
      mv "$captured" "$fallback" && scratch=""
      printf 'shot: could not reach the clipboard; saved %s\n' "$fallback" >&2
      exit 1
    fi
    ;;
  annotate | redact | text)
    # `|| status=$?` rather than a bare call: `set -e` would end the script the
    # moment satty returned non-zero, before its status could be read, so the
    # cleanup below would be skipped on exactly the runs that need it.
    tool=crop
    suffix=annotated
    if [ "$dest" = "redact" ]; then
      tool=blur
      suffix=redacted
    elif [ "$dest" = "text" ]; then
      tool=text
    fi
    output=$(unique_path "screenshot-$stamp-$suffix" png)
    status=0
    @SATTY@ --filename "$captured" --output-filename "$output" --initial-tool "$tool" || status=$?
    [ "$status" -eq 0 ] || exit "$status"
    printf 'Saved %s\n' "$output"
    ;;
  preview)
    # The copy comes first, because it is what most captures are for and it has to
    # happen whether or not the shell is up to draw anything.
    if ! @WL_COPY@ --type image/png <"$captured"; then
      printf 'shot: could not reach the clipboard\n' >&2
    fi

    # Then the preview, best effort. A shell that is not running, or one without
    # the capture target, means no window appears and nothing else changes: the
    # file is saved and on the clipboard by this point.
    @QUICKSHELL@ ipc call capture preview "$captured" >/dev/null 2>&1 || true

    printf 'Saved %s\n' "$captured"
    ;;
  save)
    if [ -n "$post" ]; then
      # shellcheck disable=SC2086
      exec $post "$captured"
    fi
    printf 'Saved %s\n' "$captured"
    ;;
esac
