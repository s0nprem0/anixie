#!/bin/bash
# The pinned webcam overlay drawn over a recording.
#
#   webcam-overlay list                    the cameras attached, one device per line
#   webcam-overlay start SIZE [DEV] [TGT]  put one up, and size it
#   webcam-overlay stop                    take it down
#   webcam-overlay resize ACTION           ACTION is small, medium, large, smaller,
#                                          larger or reset
#
# The camera is an mpv window pinned to the bottom-right corner of what is being
# recorded, cropped to 8:9 portrait. Its app-id carries the size — WebcamOverlay-
# small, -medium, -large — and the window rules in
# features/wm/hyprland/config/75-rules.lua match on that to float and pin it at
# creation. Resizing afterwards moves and
# resizes the client directly, since a window rule only applies when a window
# first appears.
#
# The three sizes are proportional to the recording, not to the monitor, so the
# camera takes the same share of a 1080p capture as of a 6K one. When a region is
# being recorded rather than a whole monitor, they scale from the region and the
# overlay anchors to the region's corner, so it stays inside the shot.
#
# gpu-screen-recorder's own device listing is used for both the camera list and
# the resolutions a camera offers, rather than v4l2-ctl: it is already a
# dependency, and it reports exactly the resolutions mpv will be asked for.

set -uo pipefail

gsr="@GSR@"
hyprctl="@HYPRCTL@"
jq="@JQ@"
mpv="@MPV@"

# Distance from the corner, in logical pixels.
MARGIN=40

# Must resolve to the same directory `record` writes the region to, or a recording
# of a region anchors the camera to the whole monitor instead. See the note on
# runtime_dir in record.sh for why the /anixie sits outside the substitution.
runtime_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie"
region_file="$runtime_dir/anixie-record.region"

# 16:9 first, widest practical first. The crop to 8:9 throws away the sides, so a
# taller source is wasted; 640x360 is enough for a corner inset and cheapest.
preferred_resolutions=(640x360 1280x720 1920x1080)

usage() {
  printf 'Usage: webcam-overlay list | start <small|medium|large> [device] [target] | stop | resize <small|medium|large|smaller|larger|reset>\n' >&2
  exit 2
}

# Every camera gpu-screen-recorder knows, deduplicated: a camera reports one line
# per resolution, and only the device is wanted here.
list_devices() {
  "$gsr" --list-v4l2-devices 2>/dev/null | awk -F'|' 'NF { if (!seen[$1]++) print $1 }'
}

# The best of the preferred resolutions this camera actually offers, as WxH.
choose_resolution() {
  local device="$1" formats res
  formats=$("$gsr" --list-v4l2-devices 2>/dev/null | awk -F'|' -v d="$device" '$1 == d { print $2 }')
  for res in "${preferred_resolutions[@]}"; do
    case "$formats" in
      *"$res@"*)
        printf '%s' "$res"
        return 0
        ;;
    esac
  done
  # Nothing preferred is on offer, so take whatever it leads with.
  printf '%s' "$formats" | head -1 | sed 's/@.*//'
}

# The running overlay's address, or empty. Matched on the app-id rather than the
# title, so an mpv playing a file called WebcamOverlay is not mistaken for it.
overlay_address() {
  "$hyprctl" clients -j 2>/dev/null |
    "$jq" -r 'first(.[] | select(.class | test("^WebcamOverlay-(small|medium|large)$"))) // empty | .address' 2>/dev/null
}

start_overlay() {
  local size="$1" device="$2" target="$3"
  local resolution capture_options

  if [ -z "$device" ]; then
    device=$(list_devices | head -1)
  fi
  if [ -z "$device" ] || [ ! -e "$device" ]; then
    printf 'webcam-overlay: no camera found\n' >&2
    return 1
  fi

  resolution=$(choose_resolution "$device")
  capture_options="framerate=30"
  [ -n "$resolution" ] && capture_options="video_size=$resolution,$capture_options"

  # The region is published before the window exists, so the size the rules are
  # chosen for and the corner they anchor to are both already known.
  if [ -n "$target" ] && [ "${target#region:}" != "$target" ]; then
    mkdir -p "$runtime_dir"
    printf '%s' "${target#region:}" >"$region_file"
  else
    rm -f "$region_file"
  fi

  # 9>&- so the overlay does not inherit and hold the recorder's lock, which would
  # stop the toggle from ever stopping the recording.
  "$mpv" "av://v4l2:$device" \
    --profile=low-latency --untimed --no-cache \
    --demuxer-lavf-o="$capture_options" \
    '--vf=lavfi=[crop=ih*8/9:ih]' \
    --title="WebcamOverlay" --wayland-app-id="WebcamOverlay-$size" \
    --no-border --no-audio --no-osc --osd-level=0 \
    --really-quiet 9>&- >/dev/null 2>&1 &
  overlay_pid=$!

  # The move has to settle before the recording starts, or the camera is caught
  # sliding into its corner. Waiting on the client appearing is what makes that
  # wait exact rather than a guess; the short sleep after covers the resize
  # dispatch below landing.
  waited=0
  while [ "$waited" -lt 40 ] && [ -z "$(overlay_address)" ]; do
    sleep 0.05
    waited=$((waited + 1))
  done

  resize "$size"

  # If it died anyway — no permission on the camera, or the device went away — say
  # so rather than let the recording start without it.
  if ! kill -0 "$overlay_pid" 2>/dev/null && [ -z "$(overlay_address)" ]; then
    printf 'webcam-overlay: mpv could not open %s\n' "$device" >&2
    return 1
  fi

  sleep 0.6
  return 0
}

stop_overlay() {
  pkill -f 'wayland-app-id=WebcamOverlay' 2>/dev/null
  rm -f "$region_file"
}

# The geometry ladder, from whatever height the overlay scales from. Heights are
# rounded to nearest rather than truncated so the three steps stay even.
#
#   small   h*9/50   and 8:9 wide    (h*4/25)
#   medium  h/4      and 8:9 wide    (h*2/9)
#   large   h*27/80  and 8:9 wide    (h*3/10)
#
# scale_height is the recording's height, capped when the recording is too narrow
# for the large preset to fit: the widest preset is 3/10 of the height, so a
# height that would make it wider than the region is brought down to match.
resize() {
  local action="$1"
  local client address monitor_id monitor_x monitor_y monitor_width monitor_height
  local anchor_x anchor_y anchor_width anchor_height scale_height available_width
  local small_w small_h medium_w medium_h large_w large_h
  local target_w target_h target_x target_y current_width current_height

  case "$action" in
    small | medium | large | smaller | larger | reset) ;;
    *)
      usage
      ;;
  esac

  client=$("$hyprctl" clients -j 2>/dev/null |
    "$jq" -cer 'first(.[] | select(.class | test("^WebcamOverlay-(small|medium|large)$"))) // empty' 2>/dev/null) || exit 0
  [ -n "$client" ] || exit 0

  read -r address current_width current_height monitor_id < <(
    "$jq" -r '[.address, .size[0], .size[1], .monitor] | @tsv' <<<"$client"
  )
  [ -n "$address" ] || exit 0
  case "$current_width" in '' | *[!0-9]*) exit 0 ;; esac
  case "$current_height" in '' | *[!0-9]*) exit 0 ;; esac

  read -r monitor_x monitor_y monitor_width monitor_height < <(
    "$hyprctl" monitors -j 2>/dev/null | "$jq" -r --argjson id "$monitor_id" '
      . as $monitors |
      first($monitors[] | select(.id == $id)) |
      . as $m |
      (($m.transform // 0) % 2 == 1) as $rotated |
      [
        .x, .y,
        (((if $rotated then .height else .width end) / .scale) | floor),
        (((if $rotated then .width else .height end) / .scale) | floor)
      ] | @tsv' 2>/dev/null
  )
  [ -n "$monitor_width" ] || exit 0

  anchor_x=$monitor_x
  anchor_y=$monitor_y
  anchor_width=$monitor_width
  anchor_height=$monitor_height

  # A recorded region takes precedence, so a window picked on a wide display keeps
  # the camera in the window's own corner rather than the monitor's.
  if [ -f "$region_file" ]; then
    region=$(cat "$region_file" 2>/dev/null)
    if [[ $region =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]]; then
      anchor_width=${BASH_REMATCH[1]}
      anchor_height=${BASH_REMATCH[2]}
      anchor_x=${BASH_REMATCH[3]}
      anchor_y=${BASH_REMATCH[4]}
    fi
  fi

  scale_height=$anchor_height
  available_width=$((anchor_width - 2 * MARGIN))
  if [ "$available_width" -gt 0 ] && [ "$((scale_height * 3 / 10))" -gt "$available_width" ]; then
    scale_height=$((available_width * 10 / 3))
  fi

  small_h=$(((scale_height * 9 + 25) / 50))
  small_w=$(((small_h * 8 + 4) / 9))
  medium_h=$(((scale_height + 2) / 4))
  medium_w=$(((medium_h * 8 + 4) / 9))
  large_h=$(((scale_height * 27 + 40) / 80))
  large_w=$(((large_h * 8 + 4) / 9))

  target_w=$current_width
  target_h=$current_height
  case "$action" in
    small)
      target_w=$small_w
      target_h=$small_h
      ;;
    medium | reset)
      target_w=$medium_w
      target_h=$medium_h
      ;;
    large)
      target_w=$large_w
      target_h=$large_h
      ;;
    smaller)
      # Step down to the next distinct size, by width. Skipping sizes already
      # matched keeps a small overlay from growing when asked to shrink.
      if [ "$large_w" -lt "$current_width" ]; then
        target_w=$large_w
        target_h=$large_h
      elif [ "$medium_w" -lt "$current_width" ]; then
        target_w=$medium_w
        target_h=$medium_h
      elif [ "$small_w" -lt "$current_width" ]; then
        target_w=$small_w
        target_h=$small_h
      fi
      ;;
    larger)
      if [ "$small_w" -gt "$current_width" ]; then
        target_w=$small_w
        target_h=$small_h
      elif [ "$medium_w" -gt "$current_width" ]; then
        target_w=$medium_w
        target_h=$medium_h
      elif [ "$large_w" -gt "$current_width" ]; then
        target_w=$large_w
        target_h=$large_h
      fi
      ;;
  esac

  target_x=$((anchor_x + anchor_width - target_w - MARGIN))
  target_y=$((anchor_y + anchor_height - target_h - MARGIN))
  # Keep the margin even when the overlay is larger than the anchor.
  [ "$target_x" -lt "$((anchor_x + MARGIN))" ] && target_x=$((anchor_x + MARGIN))
  [ "$target_y" -lt "$((anchor_y + MARGIN))" ] && target_y=$((anchor_y + MARGIN))

  window="address:$address"
  # The Lua dispatcher first, since this Hyprland reads Lua; the classic dispatcher
  # is the fallback for one that does not.
  "$hyprctl" dispatch "hl.dsp.window.resize({ window = \"$window\", x = $target_w, y = $target_h })" >/dev/null 2>&1 ||
    "$hyprctl" dispatch resizewindowpixel "exact $target_w $target_h,$window" >/dev/null 2>&1
  "$hyprctl" dispatch "hl.dsp.window.move({ window = \"$window\", x = $target_x, y = $target_y })" >/dev/null 2>&1 ||
    "$hyprctl" dispatch movewindowpixel "exact $target_x $target_y,$window" >/dev/null 2>&1
}

action="${1:-}"
case "$action" in
  list)
    list_devices
    ;;
  start)
    shift
    start_overlay "${1:-medium}" "${2:-}" "${3:-}"
    ;;
  stop)
    stop_overlay
    ;;
  resize)
    shift
    resize "${1:-reset}"
    ;;
  *)
    usage
    ;;
esac
