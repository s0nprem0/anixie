#!/bin/bash
# Choose a rectangle of the screen, and print it as "X,Y WxH".
#
#   pick                      freeform drag
#   pick windows              snaps to a window or monitor
#   pick smart                freeform, but a bare click snaps to what it lands in
#   pick fullscreen           the focused monitor, no interaction
#
#   pick --keep-freeze        leave the freeze running and write its pid to
#                             <runtime dir>/anixie-pick-freeze.pid, so a capture
#                             that follows sees the frame that was aimed at
#   pick --match-monitor      print "monitor:NAME" or "region:WxH+X+Y" instead of
#                             the raw rectangle, which is what a recorder wants
#
# While the picker is open, these are driven by keys (see the binds scoped to the
# "picker" submap in features/wm/hyprland/lua.nix):
#
#   pick --take-window        take whatever the pointer is over
#   pick --take-fullscreen    take the focused monitor
#   pick --select-window next | prev | left | right | up | down
#
# Exits 1 when the selection is cancelled, which is what a caller checks before
# capturing anything.
#
# The freeze matters more than it looks: without it the desktop keeps moving
# under the pointer, so lining up an edge on something that is animating is a
# matter of luck.

set -uo pipefail

# Private to the user where there is a runtime directory, and a directory of our
# own either way so the markers and the lock do not sit among the session's other
# files.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/anixie"
FULLSCREEN_MARKER="$runtime_dir/anixie-pick-fullscreen"
WINDOW_MARKER="$runtime_dir/anixie-pick-window"
FREEZE_PID_FILE="$runtime_dir/anixie-pick-freeze.pid"

HYPRPICKER="@HYPERPICKER@"
HYPRCTL="@HYPRCTL@"
JQ="@JQ@"

# ---- key handling ------------------------------------------------------------
#
# A key press arrives as a bind, not as input to this process, so the keys cannot
# be read here. Each one is handled by running this script again with a flag: the
# bind touches a marker file and kills the picker, and the slurp that was waiting
# returns nothing, at which point the marker says what was actually asked for.
#
# Killing slurp rather than feeding it keeps slurp out of the business of
# deciding what a key means.

if [ "${1:-}" = "--take-fullscreen" ]; then
  pgrep -x slurp >/dev/null || exit 0
  touch "$FULLSCREEN_MARKER"
  pkill -x slurp
  exit 0
fi

if [ "${1:-}" = "--take-window" ]; then
  pgrep -x slurp >/dev/null || exit 0
  touch "$WINDOW_MARKER"
  pkill -x slurp
  exit 0
fi

if [ "${1:-}" = "--select-window" ]; then
  pgrep -x slurp >/dev/null || exit 0

  direction="${2:-}"
  pos=$($HYPRCTL cursorpos)
  origin_x=${pos%,*}
  origin_y=${pos#*, }

  candidates=$(window_rects)

  # Warping the pointer to a window's centre is enough to select it, *unless*
  # something smaller sits on top of that centre — then slurp would highlight
  # the coverer, and Tab would never move. So each window is probed for a point
  # inside it that resolves back to itself, nearest the centre first, and a
  # window that cannot be reached is left out: hovering could not reach it either.
  WARP_X=0
  WARP_Y=0
  warp_points=()

  # Eighths of a rectangle, ordered by distance from its centre.
  while read -r fx fy; do
    [ -n "$fx" ] || continue
    for rect in $candidates; do
      IFS=, read -r rx ry rest <<<"$rect"
      width=${rest%x*}
      height=${rest#*x}

      # Skip a fraction of the width and height measured from the centre, so the
      # first probes land near it.
      probe_x=$((rx + width * fx / 8))
      probe_y=$((ry + height * fy / 8))

      if resolve_rect_at "$probe_x" "$probe_y" <<<"$candidates" >/dev/null &&
        [ "$RESOLVED_RECT" = "$rect" ]; then
        WARP_X=$probe_x
        WARP_Y=$probe_y
        warp_points+=("$rect $WARP_X $WARP_Y")
        break
      fi
    done
  done <<<"$(for fx in 1 2 3 4 5 6 7; do
    for fy in 1 2 3 4 5 6 7; do
      echo "$(( ((fx - 4) * (fx - 4) + (fy - 4) * (fy - 4)) )) $fx $fy"
    done
  done | sort -n | cut -d' ' -f2-)"

  [ ${#warp_points[@]} -gt 0 ] || exit 0

  # Reading order: top to bottom, then left to right.
  rects=$(printf '%s\n' "${warp_points[@]}" |
    awk '{
      split($1, a, ",")
      split($2, b, "x")
      printf "%d\t%d\t%s\n", a[2], a[1], $1
    }' | sort -n -k1,1 -k2,2 | cut -f3-)

  current=""
  if resolve_rect_at "$origin_x" "$origin_y" <<<"$candidates"; then
    current="$RESOLVED_RECT"
  fi

  target=""

  case "$direction" in
    next | prev)
      mapfile -t ordered <<<"$rects"
      count=${#ordered[@]}
      current_index=-1
      for i in "${!ordered[@]}"; do
        if [ -n "$current" ] && [ "${ordered[$i]}" = "$current" ]; then
          current_index=$i
          break
        fi
      done

      if [ "$direction" = "next" ]; then
        if [ "$current_index" -lt 0 ]; then
          target="${ordered[$((count - 1))]}"
        else
          target="${ordered[$(((current_index + 1) % count))]}"
        fi
      else
        if [ "$current_index" -lt 0 ]; then
          target="${ordered[$((count - 1))]}"
        else
          target="${ordered[$(((current_index - 1 + count) % count))]}"
        fi
      fi
      ;;
    left | right | up | down)
      # The window whose centre is furthest in that direction, with sideways
      # offset counted double: a window that is a little past but well aligned is
      # nearer than one directly across and far off.
      best_score=""
      for rect in $rects; do
        [ "$rect" = "$current" ] && continue
        IFS=, read -r rx ry rest <<<"$rect"
        width=${rest%x*}
        height=${rest#*x}
        centre_x=$((rx + width / 2))
        centre_y=$((ry + height / 2))

        case "$direction" in
          left) primary=$((origin_x - centre_x)); perp=$((centre_y - origin_y)) ;;
          right) primary=$((centre_x - origin_x)); perp=$((centre_y - origin_y)) ;;
          up) primary=$((origin_y - centre_y)); perp=$((centre_x - origin_x)) ;;
          down) primary=$((centre_y - origin_y)); perp=$((centre_x - origin_x)) ;;
        esac

        [ "$primary" -gt 0 ] || continue
        [ "$perp" -lt 0 ] && perp=$((-perp))
        score=$((primary + perp * 2))

        if [ -z "$best_score" ] || [ "$score" -lt "$best_score" ]; then
          best_score="$score"
          target="$rect"
        fi
      done
      ;;
    *)
      exit 1
      ;;
  esac

  if [ -n "$target" ]; then
    for entry in "${warp_points[@]}"; do
      read -r rect wx wy <<<"$entry"
      if [ "$rect" = "$target" ]; then
        # hyprctl moves the pointer, which is what makes slurp re-evaluate what
        # it is highlighting. Warping through the compositor rather than writing
        # to the devices keeps it in step with the grab slurp holds.
        $HYPRCTL eval "hl.dispatch(hl.dsp.cursor.move({ x = $wx, y = $wy }))" >/dev/null 2>&1
        break
      fi
    done
  fi
  exit 0
fi

# ---- rectangles --------------------------------------------------------------

active_workspace() {
  $HYPRCTL monitors -j | $JQ -r '.[] | select(.focused == true) | .activeWorkspace.id'
}

# Monitor geometry as slurp wants it: unscaled, and with width and height
# swapped for a rotated or flipped output, since slurp's coordinates are the
# ones on screen.
monitor_rects() {
  $HYPRCTL monitors -j | $JQ -r --arg ws "$(active_workspace)" '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale | floor) as $w |
      (.height / .scale | floor) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    .[] | select(.activeWorkspace.id == ($ws | tonumber)) | format_geo'
}

window_rects() {
  $HYPRCTL clients -j | $JQ -r --arg ws "$(active_workspace)" \
    '[.[] | select(.workspace.id == ($ws | tonumber) and .hidden != true) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"] | unique[]'
}

# Every rectangle worth snapping to, deduplicated across the two lists. A
# maximized window reports the same rectangle as its monitor, and without the
# sort -u that rectangle appears twice — which matters wherever the first match
# wins rather than the smallest.
all_rects() {
  { monitor_rects; window_rects; } | sort -u
}

# Monitor name and rectangle, tab-separated, so a caller can go from a picked
# rectangle back to the monitor it *is*. gpu-screen-recorder records a monitor by
# name at native resolution, which is both cheaper and sharper than feeding it the
# same rectangle as a region, so a whole-monitor pick should stay a monitor pick.
monitor_named_rects() {
  $HYPRCTL monitors -j | $JQ -r --arg ws "$(active_workspace)" '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale | floor) as $w |
      (.height / .scale | floor) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    .[] | select(.activeWorkspace.id == ($ws | tonumber)) | "\(.name)\t\(format_geo)"'
}

focused_monitor_geo() {
  $HYPRCTL monitors -j | $JQ -r '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale | floor) as $w |
      (.height / .scale | floor) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    .[] | select(.focused == true) | format_geo'
}

# Which rectangle of the candidates contains this point. slurp highlights the
# smallest box containing the pointer and keeps the first on a tie, so the same
# rule is applied here — otherwise Tab and Enter would disagree with what is on
# screen when a floating window sits over a tiled one.
RESOLVED_RECT=""
resolve_rect_at() {
  local x=$1 y=$2 rect area
  local smallest_area=0

  RESOLVED_RECT=""

  while read -r rect; do
    [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
    ((x >= BASH_REMATCH[1] && x < BASH_REMATCH[1] + BASH_REMATCH[3] &&
      y >= BASH_REMATCH[2] && y < BASH_REMATCH[2] + BASH_REMATCH[4])) || continue

    area=$((BASH_REMATCH[3] * BASH_REMATCH[4]))
    if [ -z "$RESOLVED_RECT" ] || ((area < smallest_area)); then
      RESOLVED_RECT=$rect
      smallest_area=$area
    fi
  done

  [ -n "$RESOLVED_RECT" ]
}

rects_for_point() {
  local x=$1 y=$2
  if resolve_rect_at "$x" "$y" <<<"$(window_rects)"; then
    echo "$RESOLVED_RECT"
  elif resolve_rect_at "$x" "$y" <<<"$(monitor_rects)"; then
    echo "$RESOLVED_RECT"
  else
    focused_monitor_geo
  fi
}

# ---- the freeze --------------------------------------------------------------

FREEZE_PID=""
freeze_screen() {
  # hyprpicker is what freezes: it puts a still frame of the screen up before
  # slurp draws on it, so the desktop cannot keep moving under the pointer while
  # an edge is being lined up on something animating.
  #
  #   -r  render inactive displays as well, so a multi-monitor setup freezes as a
  #       whole rather than only the focused output.
  #   -z  no zoom lens. The lens magnifies under the cursor and would sit on top
  #       of the very region being picked.
  #
  # It is killed on exit, so the frame comes down with the selection made against
  # it and the capture that follows still sees what was picked.
  "$HYPRPICKER" -r -z >/dev/null 2>&1 &
  FREEZE_PID=$!
  sleep 0.1
}

cleanup_freeze() {
  [ "${KEEP_FREEZE:-false}" = "true" ] && return
  [ -n "$FREEZE_PID" ] && kill "$FREEZE_PID" 2>/dev/null
}

# Run slurp and work out what was chosen. An empty result with a marker present
# means a key was pressed rather than a drag made.
pick() {
  local selection
  rm -f "$FULLSCREEN_MARKER" "$WINDOW_MARKER"
  selection=$(slurp "$@" 2>/dev/null)

  if [ -z "$selection" ] && [ -e "$FULLSCREEN_MARKER" ]; then
    rm -f "$FULLSCREEN_MARKER"
    selection=$(focused_monitor_geo)
  elif [ -z "$selection" ] && [ -e "$WINDOW_MARKER" ]; then
    rm -f "$WINDOW_MARKER"
    pos=$($HYPRCTL cursorpos)
    selection=$(rects_for_point "${pos%,*}" "${pos#*, }")
  fi

  printf '%s' "$selection"
}

# ---- modes -------------------------------------------------------------------

MODE=""
KEEP_FREEZE="false"
MATCH_MONITOR="false"

# Flags are position-independent, so a caller can say `pick smart --match-monitor`
# without having to know which argument the mode is.
for arg in "$@"; do
  case "$arg" in
    smart | region | windows | fullscreen | window) MODE="$arg" ;;
    --keep-freeze) KEEP_FREEZE="true" ;;
    --match-monitor) MATCH_MONITOR="true" ;;
  esac
done
MODE="${MODE:-smart}"

# ---- one picker at a time ----------------------------------------------------
#
# The marker files carry fixed names, so two captures overlapping would clear each
# other's markers and whichever lost the race would come back looking cancelled.
# A marker orphaned by a crashed run is worse: it survives into the *next*
# capture, which then silently becomes a fullscreen grab nobody asked for.
#
# `rm -f` only inside pick() is not enough for either — it runs after the freeze,
# and a second capture can clear the markers in between. Serializing whole
# selections here, with the markers cleared inside the lock, covers both.
#
# Only this path takes the lock. The `--take-*` and `--select-window` handlers
# above run *while* this process is waiting on slurp, and would deadlock against
# it if they waited for the lock too. `flock` on an fd held open for the rest of
# the script releases when the script exits, however it exits.
#
# `exec` rather than a subshell because the lock has to be held across the whole
# of the capture below, not just its acquisition.
mkdir -p "$runtime_dir"
exec 9>"$runtime_dir/anixie-pick.lock"
flock 9 || printf 'pick: could not lock %s\n' "$runtime_dir/anixie-pick.lock" >&2

rm -f "$FULLSCREEN_MARKER" "$WINDOW_MARKER"

# ---- the picker's keys -------------------------------------------------------
#
# The keys that drive the selection — Return takes the window under the pointer,
# Tab walks the windows, the arrows extend — are bound to this script inside a
# Hyprland submap, and a submap is only live while it is entered. Entering it here
# rather than in the bind is what makes those keys work however the picker was
# reached: from a key, from the menu, or from a terminal. They used to be the
# bind's business, so a capture started from the menu had no keyboard at all.
#
# A submap that never comes down takes every other bind on the desktop with it —
# Super+Return included — so the reset is on the way out as well, on every exit
# path including a cancelled selection. The bind still resets afterwards as well;
# this is the one that cannot miss.
#
# Only when there is a picker. `fullscreen` asks nothing, so there is nothing for
# a submap to serve, and entering one would disable the desktop's keys for the
# moment it took to work that out.
entered_submap="false"
if [ "$MODE" != "fullscreen" ]; then
  $HYPRCTL dispatch 'hl.dsp.submap("picker")' >/dev/null 2>&1
  entered_submap="true"
fi

# One exit handler for both, because a second `trap` would replace the first and
# whichever was set last would be the only one that ran: the submap would come
# down and the freeze would stay up, or the other way round.
cleanup_picker() {
  cleanup_freeze
  [ "$entered_submap" = "true" ] && $HYPRCTL dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1
}
trap cleanup_picker EXIT HUP INT TERM

SELECTION=""

case "$MODE" in
fullscreen)
  # No picker, so nothing is frozen and nothing is asked.
  SELECTION=$(focused_monitor_geo)
  ;;
region)
  # No rectangles at all: any drag, anywhere.
  freeze_screen
  SELECTION=$(pick -d)
  ;;
windows)
  # -r restricts the selection to the rectangles, so it can only ever end up
  # being exactly one window or monitor.
  freeze_screen
  SELECTION=$(all_rects | pick -d -r)
  ;;
smart | *)
  # The rectangles are given to slurp so it highlights and snaps to them, but -r
  # is left off so a freeform drag is still allowed: you can either drag an edge
  # or click a window and get all of it.
  RECTS=$(all_rects)
  freeze_screen
  SELECTION=$(echo "$RECTS" | pick -d)

  # A click rather than a drag comes back as a rectangle of almost no area, which
  # is never something anyone meant. Snapped to whichever rectangle it landed in.
  #
  # Which rectangle is `resolve_rect_at`'s question, not a first-match loop over
  # the list: a click is always inside the monitor, so a first-match loop stops
  # there and a click meant for a window captures the whole screen instead. The
  # smallest rectangle containing the point is what slurp highlights, and it is
  # what the keyboard path already uses, so both agree.
  if [[ $SELECTION =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] &&
    ((BASH_REMATCH[3] * BASH_REMATCH[4] < 20)); then
    if resolve_rect_at "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" <<<"$RECTS"; then
      SELECTION="$RESOLVED_RECT"
    fi
  fi
  ;;
esac

# The freeze's pid goes to a file rather than to stdout. A caller that keeps the
# freeze wants it across a capture that happens after this process has exited, and
# a pid line mixed into the output would have to be told apart from the geometry on
# every read.
if [ "$KEEP_FREEZE" = "true" ] && [ -n "$FREEZE_PID" ]; then
  printf '%s' "$FREEZE_PID" >"$FREEZE_PID_FILE"
fi

[ -n "$SELECTION" ] || exit 1

# `--match-monitor` re-expresses the rectangle as something gpu-screen-recorder
# takes directly: `monitor:NAME` when the pick is exactly a monitor, and
# `region:WxH+X+Y` otherwise. The offsets move to the end because that is the
# order gsr's `-region` wants, and the comma slurp uses is not part of it.
if [ "$MATCH_MONITOR" = "true" ]; then
  matched_monitor=$(monitor_named_rects | awk -F'\t' -v sel="$SELECTION" '$2 == sel { print $1; exit }')
  if [ -n "$matched_monitor" ]; then
    SELECTION="monitor:$matched_monitor"
  elif [[ $SELECTION =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    SELECTION="region:${BASH_REMATCH[3]}x${BASH_REMATCH[4]}+${BASH_REMATCH[1]}+${BASH_REMATCH[2]}"
  fi
fi

echo "$SELECTION"