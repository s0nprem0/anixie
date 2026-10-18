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
#   preview   save it, copy it, and show it for ten seconds — the default
#   save      write a PNG into $SHOT_DIR (default ~/Pictures/Screenshots) and stop
#   copy      put it on the clipboard and write nothing
#   annotate  open it in satty, which starts in crop mode, and save the result
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
# to `shot-pick` against the picker's submap in features/wm/hyprland/lua.nix.

set -eu

shot_dir="${SHOT_DIR:-$HOME/Pictures/Screenshots}"

mode="smart"
dest="preview"
post=""

usage() {
  # The header comment is the manual, so it is printed rather than copied out a
  # second time, where it would drift. It runs from line 2 to the first line that
  # is not a comment — which is `set -eu` — and that line is dropped.
  #
  # Line 2, not 1: the file Home Manager installs has its own shebang prepended,
  # so this script's `#!/bin/sh` is line 2 and would otherwise print as `!/bin/sh`
  # once the leading `#` is stripped. Any shebang line left in range goes first.
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
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
    save | copy | annotate | preview)
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

# `-- CMD` runs against a file that is kept, so it cannot be combined with a
# destination that keeps nothing (copy) or keeps a different file (annotate).
if [ -n "$post" ] && [ "$dest" != "save" ]; then
  printf 'shot: -- CMD cannot be combined with "%s"\n' "$dest" >&2
  exit 2
fi

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
  geometry=$(@SHOT_PICK@ "$mode" --keep-freeze) || exit 1
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
  copy | annotate)
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
@GRIM@ -c -g "$geometry" "$captured"

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
  annotate)
    # `|| status=$?` rather than a bare call: `set -e` would end the script the
    # moment satty returned non-zero, before its status could be read, so the
    # cleanup below would be skipped on exactly the runs that need it.
    output=$(unique_path "screenshot-$stamp-annotated" png)
    status=0
    @SATTY@ --filename "$captured" --output-filename "$output" --initial-tool crop || status=$?
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
