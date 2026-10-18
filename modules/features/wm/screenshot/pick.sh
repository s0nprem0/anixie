#!/bin/bash
# Choose a rectangle of the screen, and print it as "X,Y WxH".
#
#   pick                      freeform drag
#   pick windows              snaps to a window or monitor
#   pick smart                freeform, but a bare click snaps to what it lands in
#   pick fullscreen           the focused monitor, no interaction
#
#   pick --keep-freeze        leave the freeze running and print its pid first
#
# While the picker is open, these are driven by keys (see the binds scoped to the
# selection layer in features/wm/hyprland/keybinds.nix):
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

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
FULLSCREEN_MARKER="$runtime_dir/anixie-pick-fullscreen"
WINDOW_MARKER="$runtime_dir/anixie-pick-window"

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
  reachable=""
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
  # -r keeps the frozen frame on screen after it is dismissed, so the capture
  # that follows still sees what was picked rather than whatever moved since.
  "$HYPRPICKER" -r -z >/dev/null 2>&1 &
  FREEZE_PID=$!
  sleep 0.1
}

cleanup_freeze() {
  [ "${KEEP_FREEZE:-false}" = "true" ] && return
  [ -n "$FREEZE_PID" ] && kill "$FREEZE_PID" 2>/dev/null
}
trap cleanup_freeze EXIT

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

MODE="${1:-smart}"
KEEP_FREEZE="false"
[ "${2:-}" = "--keep-freeze" ] && KEEP_FREEZE="true"

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
  SELECTION=$(echo "$(monitor_rects; window_rects)" | pick -d -r)
  ;;
smart | *)
  # The rectangles are given to slurp so it highlights and snaps to them, but -r
  # is left off so a freeform drag is still allowed: you can either drag an edge
  # or click a window and get all of it.
  RECTS=$(monitor_rects; window_rects)
  freeze_screen
  SELECTION=$(echo "$RECTS" | pick -d)

  # A click rather than a drag comes back as a rectangle of almost no area, which
  # is never something anyone meant. Snapped to whichever rectangle it landed in.
  if [[ $SELECTION =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] &&
    ((BASH_REMATCH[3] * BASH_REMATCH[4] < 20)); then
    click_x=${BASH_REMATCH[1]}
    click_y=${BASH_REMATCH[2]}

    while read -r rect; do
      [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
      ((click_x >= BASH_REMATCH[1] && click_x < BASH_REMATCH[1] + BASH_REMATCH[3] &&
        click_y >= BASH_REMATCH[2] && click_y < BASH_REMATCH[2] + BASH_REMATCH[4])) || continue
      SELECTION="${BASH_REMATCH[1]},${BASH_REMATCH[2]} ${BASH_REMATCH[3]}x${BASH_REMATCH[4]}"
      break
    done <<<"$RECTS"
  fi
  ;;
esac

[ "$KEEP_FREEZE" = "true" ] && echo "$FREEZE_PID"
[ -n "$SELECTION" ] || exit 1

echo "$SELECTION"