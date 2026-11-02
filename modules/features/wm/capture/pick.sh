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

set -uo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/anixie"
FULLSCREEN_MARKER="$runtime_dir/anixie-pick-fullscreen"
WINDOW_MARKER="$runtime_dir/anixie-pick-window"
FREEZE_PID_FILE="$runtime_dir/anixie-pick-freeze.pid"
SESSION_FILE="$runtime_dir/anixie-pick-session"
LOCK_FILE="$runtime_dir/anixie-pick.lock"

HYPRPICKER="@HYPERPICKER@"
HYPRCTL="@HYPRCTL@"
JQ="@JQ@"

SESSION_ID="$$-$(date +%s%N 2>/dev/null || date +%s)"
SUBMAP_ACTIVE=0

cleanup() {
  local rc=$?
  if [ $SUBMAP_ACTIVE -eq 1 ]; then
    $HYPRCTL dispatch submap reset >/dev/null 2>&1 || true
    SUBMAP_ACTIVE=0
  fi
  cleanup_freeze || true
  if [ "${KEEP_FREEZE:-false}" != "true" ]; then
    rm -f "$FREEZE_PID_FILE" 2>/dev/null || true
  fi
  rm -f "$FULLSCREEN_MARKER.$SESSION_ID" "$WINDOW_MARKER.$SESSION_ID" 2>/dev/null || true
  if [ "${IS_PRIMARY:-false}" = "true" ]; then
    rm -f "$SESSION_FILE" 2>/dev/null || true
  fi
  exit $rc
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# ---- key handling ------------------------------------------------------------

if [ "${1:-}" = "--take-fullscreen" ]; then
  sid=""
  [ -r "$SESSION_FILE" ] && sid=$(cat "$SESSION_FILE" 2>/dev/null || true)
  if [ -n "$sid" ]; then
    pidf="$runtime_dir/anixie-pick-$sid.pid"
    [ -r "$pidf" ] && pkill -P "$(cat "$pidf")" 2>/dev/null || true
  fi
  pgrep -x slurp >/dev/null && pkill -x slurp 2>/dev/null || true
  touch "$FULLSCREEN_MARKER${sid:+.$sid}"
  exit 0
fi

if [ "${1:-}" = "--take-window" ]; then
  sid=""
  [ -r "$SESSION_FILE" ] && sid=$(cat "$SESSION_FILE" 2>/dev/null || true)
  if [ -n "$sid" ]; then
    pidf="$runtime_dir/anixie-pick-$sid.pid"
    [ -r "$pidf" ] && pkill -P "$(cat "$pidf")" 2>/dev/null || true
  fi
  pgrep -x slurp >/dev/null && pkill -x slurp 2>/dev/null || true
  touch "$WINDOW_MARKER${sid:+.$sid}"
  exit 0
fi

if [ "${1:-}" = "--select-window" ]; then
  pgrep -x slurp >/dev/null || exit 0
  direction="${2:-}"
  pos=$($HYPRCTL cursorpos 2>/dev/null || echo "0,0")
  origin_x=${pos%,*}
  origin_y=${pos#*, }
  [ -z "$origin_x" ] && origin_x=0
  [ -z "$origin_y" ] && origin_y=0

  candidates=$(window_rects 2>/dev/null || true)
  [ -z "$candidates" ] && exit 0

  mapfile -t cand_arr <<<"$candidates"
  [ ${#cand_arr[@]} -eq 0 ] && exit 0

  declare -a warp_entries=()
  local_i=0
  for rect in "${cand_arr[@]}"; do
    [ -z "$rect" ] && continue
    if [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
      rx=${BASH_REMATCH[1]}; ry=${BASH_REMATCH[2]}; rw=${BASH_REMATCH[3]}; rh=${BASH_REMATCH[4]}
      [ "$rw" -le 0 ] || [ "$rh" -le 0 ] && continue
      cx=$((rx + rw / 2))
      cy=$((ry + rh / 2))
      warp_entries+=("$rect|$cx|$cy")
    fi
  done
  [ ${#warp_entries[@]} -eq 0 ] && exit 0

  # sort by y then x
  mapfile -t ordered < <(printf '%s\n' "${warp_entries[@]}" | awk -F'|' '{split($1,a,","); split($1,b," "); split(b[2],d,"x"); print a[2]"\t"a[1]"\t"$1"\t"$2"\t"$3}' | sort -n -k1,1 -k2,2 | cut -f3-)

  current=""
  if resolve_rect_at "$origin_x" "$origin_y" <<<"$candidates" 2>/dev/null; then
    current="$RESOLVED_RECT"
  fi

  target=""
  case "$direction" in
    next|prev)
      mapfile -t oarr <<<"$ordered"
      count=${#oarr[@]}
      cidx=-1
      for i in "${!oarr[@]}"; do
        IFS='|' read -r or_ wx wy <<<"${oarr[$i]}"
        if [ -n "$current" ] && [ "$or_" = "$current" ]; then cidx=$i; break; fi
      done
      if [ "$direction" = "next" ]; then
        if [ "$cidx" -lt 0 ]; then target="${oarr[$((count-1))]}"; else target="${oarr[$(((cidx+1)%count))]}"; fi
      else
        if [ "$cidx" -lt 0 ]; then target="${oarr[$((count-1))]}"; else target="${oarr[$(((cidx-1+count)%count))]}"; fi
      fi
      ;;
    left|right|up|down)
      best_score=""
      best_target=""
      for entry in "${ordered[@]}"; do
        IFS='|' read -r or_ wx wy <<<"$entry"
        [ "$or_" = "$current" ] && continue
        IFS=, read -r rx ry rest <<<"$or_"
        width=${rest%x*}; height=${rest#*x}
        [ -z "$width" ] || [ -z "$height" ] && continue
        cx=$((rx+width/2)); cy=$((ry+height/2))
        case "$direction" in
          left) primary=$((origin_x-cx)); perp=$((cy-origin_y));;
          right) primary=$((cx-origin_x)); perp=$((cy-origin_y));;
          up) primary=$((origin_y-cy)); perp=$((cx-origin_x));;
          down) primary=$((cy-origin_y)); perp=$((cx-origin_x));;
        esac
        [ "$primary" -le 0 ] && continue
        [ "$perp" -lt 0 ] && perp=$((-perp))
        score=$((primary + perp*2))
        if [ -z "$best_score" ] || [ "$score" -lt "$best_score" ]; then
          best_score=$score; best_target="$entry"
        elif [ "$score" -eq "$best_score" ] && [ -z "$best_target" ]; then
          best_target="$entry"
        fi
      done
      target="$best_target"
      ;;
    *) exit 1 ;;
  esac

  if [ -n "$target" ]; then
    IFS='|' read -r tr wx wy <<<"$target"
    $HYPRCTL eval "hl.dispatch(hl.dsp.cursor.move({ x = $wx, y = $wy }))" >/dev/null 2>&1 || true
  fi
  exit 0
fi

# ---- rectangles --------------------------------------------------------------

active_workspace() {
  $HYPRCTL monitors -j 2>/dev/null | $JQ -r '.[] | select(.focused == true) | .activeWorkspace.id' 2>/dev/null || echo ""
}

format_monitor_geo() {
  $JQ -r '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale) as $fw |
      (.height / .scale) as $fh |
      ($fw | round) as $w |
      ($fh | round) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    format_geo'
}

monitor_rects() {
  local ws
  ws="$(active_workspace)"
  if [ -n "$ws" ]; then
    $HYPRCTL monitors -j 2>/dev/null | $JQ -r --arg ws "$ws" '.[] | select(.activeWorkspace.id == ($ws | tonumber))' 2>/dev/null | format_monitor_geo
  else
    $HYPRCTL monitors -j 2>/dev/null | $JQ -r '.[]' 2>/dev/null | format_monitor_geo
  fi
}

window_rects() {
  local ws
  ws="$(active_workspace)"
  if [ -n "$ws" ]; then
    $HYPRCTL clients -j 2>/dev/null | $JQ -r --arg ws "$ws" '[.[] | select(.workspace.id == ($ws | tonumber) and .hidden != true and (.at|length)==2 and (.size|length)==2) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"] | unique[]' 2>/dev/null
  else
    $HYPRCTL clients -j 2>/dev/null | $JQ -r '[.[] | select(.hidden != true and (.at|length)==2 and (.size|length)==2) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"] | unique[]' 2>/dev/null
  fi
}

all_rects() {
  { monitor_rects; window_rects; }
}

monitor_named_rects() {
  $HYPRCTL monitors -j 2>/dev/null | $JQ -r '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale) as $fw |
      (.height / .scale) as $fh |
      ($fw | round) as $w |
      ($fh | round) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    .[] | "\(.name)\t\(format_geo)"
  ' 2>/dev/null
}

focused_monitor_geo() {
  $HYPRCTL monitors -j 2>/dev/null | $JQ -r '
    def format_geo:
      .x as $x | .y as $y |
      (.width / .scale) as $fw |
      (.height / .scale) as $fh |
      ($fw | round) as $w |
      ($fh | round) as $h |
      .transform as $t |
      if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
      else "\($x),\($y) \($w)x\($h)" end;
    .[] | select(.focused == true) | format_geo'
}

RESOLVED_RECT=""
resolve_rect_at() {
  local x=$1 y=$2 rect
  local smallest_area=0
  RESOLVED_RECT=""
  while read -r rect; do
    [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
    ((x >= BASH_REMATCH[1] && x < BASH_REMATCH[1] + BASH_REMATCH[3] &&
      y >= BASH_REMATCH[2] && y < BASH_REMATCH[2] + BASH_REMATCH[4])) || continue
    local area=$((BASH_REMATCH[3] * BASH_REMATCH[4]))
    if [ -z "$RESOLVED_RECT" ] || ((area < smallest_area)); then
      RESOLVED_RECT=$rect
      smallest_area=$area
    fi
  done
  [ -n "$RESOLVED_RECT" ]
}

rects_for_point() {
  local x=$1 y=$2
  if resolve_rect_at "$x" "$y" <<<"$(window_rects 2>/dev/null)"; then
    echo "$RESOLVED_RECT"; return
  fi
  if resolve_rect_at "$x" "$y" <<<"$(monitor_rects 2>/dev/null)"; then
    echo "$RESOLVED_RECT"; return
  fi
  focused_monitor_geo 2>/dev/null
}

# ---- freeze --------------------------------------------------------------

FREEZE_PID=""
freeze_screen() {
  command -v "$HYPRPICKER" >/dev/null 2>&1 || return 1
  "$HYPRPICKER" -r -z >/dev/null 2>&1 &
  FREEZE_PID=$!
  local i=0
  while [ $i -lt 20 ]; do
    kill -0 "$FREEZE_PID" 2>/dev/null || break
    sleep 0.01
    i=$((i+1))
  done
  kill -0 "$FREEZE_PID" 2>/dev/null || return 1
  return 0
}

cleanup_freeze() {
  [ "${KEEP_FREEZE:-false}" = "true" ] && return 0
  if [ -n "$FREEZE_PID" ]; then
    kill "$FREEZE_PID" 2>/dev/null || true
    wait "$FREEZE_PID" 2>/dev/null || true
    FREEZE_PID=""
  fi
  return 0
}

# ---- pick --------------------------------------------------------------

pick() {
  local selection=""
  rm -f "$FULLSCREEN_MARKER" "$WINDOW_MARKER" "$FULLSCREEN_MARKER.$SESSION_ID" "$WINDOW_MARKER.$SESSION_ID"
  echo "$SESSION_ID" > "$SESSION_FILE" 2>/dev/null || true
  echo "$$" > "$runtime_dir/anixie-pick-$SESSION_ID.pid" 2>/dev/null || true
  slurp_bg="${SLURP_BG:-#00000066}"
  slurp_border="${SLURP_BORDER:-#cdd6f4}"
  slurp_select="${SLURP_SELECT:-#cdd6f422}"
  slurp_box="${SLURP_BOX:-#1e1e2ecc}"
  slurp_font="${SLURP_FONT:-JetBrainsMono Nerd Font}"
  selection=$(slurp -d -b "$slurp_bg" -c "$slurp_border" -w 2 -s "$slurp_select" -B "$slurp_box" -F "$slurp_font" "$@" 2>/dev/null) || selection=""
  if [ -z "$selection" ] && [ -e "$FULLSCREEN_MARKER.$SESSION_ID" ]; then
    rm -f "$FULLSCREEN_MARKER.$SESSION_ID"
    selection=$(focused_monitor_geo 2>/dev/null || true)
  elif [ -z "$selection" ] && [ -e "$WINDOW_MARKER.$SESSION_ID" ]; then
    rm -f "$WINDOW_MARKER.$SESSION_ID"
    pos=$($HYPRCTL cursorpos 2>/dev/null || echo "0,0")
    selection=$(rects_for_point "${pos%,*}" "${pos#*, }" 2>/dev/null || true)
  fi
  printf '%s' "$selection"
}

# ---- modes -------------------------------------------------------------------

MODE=""
KEEP_FREEZE="false"
MATCH_MONITOR="false"

for arg in "$@"; do
  case "$arg" in
    smart|region|windows|fullscreen|window) MODE="$arg" ;;
    --keep-freeze) KEEP_FREEZE="true" ;;
    --match-monitor) MATCH_MONITOR="true" ;;
  esac
done
MODE="${MODE:-smart}"

mkdir -p "$runtime_dir"
IS_PRIMARY="true"
exec 9>"$LOCK_FILE"
if ! flock -n 9 2>/dev/null; then
  echo "pick: could not acquire lock" >&2
  exit 2
fi

rm -f "$FULLSCREEN_MARKER" "$WINDOW_MARKER" "$FULLSCREEN_MARKER.$SESSION_ID" "$WINDOW_MARKER.$SESSION_ID"

# enter submap for interactive modes
case "$MODE" in
  region|smart|windows|window)
    if $HYPRCTL dispatch submap picker >/dev/null 2>&1; then
      SUBMAP_ACTIVE=1
    fi
    ;;
esac

case "$MODE" in
  fullscreen)
    SELECTION=$(focused_monitor_geo 2>/dev/null || true)
    ;;
  windows)
    mapfile -t rects < <(all_rects 2>/dev/null)
    (( ${#rects[@]} )) || { echo "pick: no rectangles" >&2; exit 1; }
    SELECTION=$(pick -f '%x,%y %wx%h' -r "${rects[@]}") || exit 1
    ;;
  smart)
    freeze_screen || true
    SELECTION=$(pick 2>/dev/null) || exit 1
    ;;
  region)
    freeze_screen || true
    SELECTION=$(pick 2>/dev/null) || exit 1
    ;;
  window)
    freeze_screen || true
    SELECTION=$(pick -f '%x,%y %wx%h' -r "${rects_for_point:-}" 2>/dev/null) || true
    if [ -z "$SELECTION" ]; then
      pos=$($HYPRCTL cursorpos 2>/dev/null || echo "0,0")
      SELECTION=$(rects_for_point "${pos%,*}" "${pos#*, }" 2>/dev/null || true)
    fi
    ;;
  *)
    SELECTION=""
    ;;
esac

# click snapping for smart
if [ "$MODE" = "smart" ] && [[ $SELECTION =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
  if (( ${BASH_REMATCH[3]} * ${BASH_REMATCH[4]} < 20 )); then
    if resolve_rect_at "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" <<<"$( { window_rects; monitor_rects; } 2>/dev/null )"; then
      SELECTION="$RESOLVED_RECT"
    fi
  fi
fi

if [ "$KEEP_FREEZE" = "true" ] && [ -n "$FREEZE_PID" ]; then
  printf '%s' "$FREEZE_PID" >"$FREEZE_PID_FILE" 2>/dev/null || true
fi

[ -n "${SELECTION:-}" ] || exit 1

if [ "$MATCH_MONITOR" = "true" ]; then
  if [[ $SELECTION =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    cx=$(( ${BASH_REMATCH[1]} + ${BASH_REMATCH[3]} / 2 ))
    cy=$(( ${BASH_REMATCH[2]} + ${BASH_REMATCH[4]} / 2 ))
    mon=$($HYPRCTL monitors -j 2>/dev/null | $JQ -r --argjson x "$cx" --argjson y "$cy" '
      .[] | select(
        (.x <= $x) and ($x < (.x + (.width / .scale))) and
        (.y <= $y) and ($y < (.y + (.height / .scale)))
      ) | .name' | head -n1)
    if [ -n "$mon" ]; then
      SELECTION="monitor:$mon"
    else
      SELECTION="region:${BASH_REMATCH[3]}x${BASH_REMATCH[4]}+${BASH_REMATCH[1]}+${BASH_REMATCH[2]}"
    fi
  fi
fi

echo "$SELECTION"
