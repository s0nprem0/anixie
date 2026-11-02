internal_output() {
  case "$1" in
    eDP* | LVDS* | DSI*) return 0 ;;
    *) return 1 ;;
  esac
}

# The I2C bus for an external output, cached because ddcutil detect is slow and
# a repeating brightness key should not pay for it on every press. A stale cache
# is dropped by the caller when getvcp fails.
ddc_bus_for() {
  local output="$1" cache="$state_dir/ddc-$1" bus
  if [ -f "$cache" ]; then
    bus=$(cat "$cache" 2>/dev/null || true)
    if [ -n "$bus" ]; then
      printf '%s' "$bus"
      return 0
    fi
  fi

  bus=$("$ddcutil" detect --brief 2>/dev/null | awk -v out="$output" '
    /^Display / { display = $2 }
    /I2C bus:/ { bus = $3; sub("/dev/i2c-", "", bus) }
    /DRM connector:/ {
      conn = $3
      sub("^card[0-9]+-", "", conn)
      if (conn == out) { print bus; exit }
    }
  ')
  [ -n "$bus" ] || return 1

  mkdir -p "$state_dir" || die "could not create $state_dir"
  printf '%s\n' "$bus" >"$cache"
  printf '%s' "$bus"
}

brightness_internal() {
  local action="$1" step="$2"
  case "$action" in
    up) "$brightnessctl" set "+${step}%" ;;
    down) "$brightnessctl" set "${step}%-" ;;
    set) "$brightnessctl" set "${step}%" ;;
    max) "$brightnessctl" set 100% ;;
    min) "$brightnessctl" set 1% ;;
    show) "$brightnessctl" --machine-readable ;;
    *) die "brightness takes up, down, set N, max, min, or show" ;;
  esac
}

osd_message() {
  "$quickshell" ipc call osd payload \
    "{\"icon\":\"brightness\",\"message\":\"$1\"}" >/dev/null 2>&1 || true
}

brightness_external() {
  local output="$1" action="$2" step="$3" bus reading current max target
  bus=$(ddc_bus_for "$output") || {
    osd_message "No DDC/CI brightness on this display"
    die "no DDC/CI display for $output"
  }

  reading=$("$ddcutil" -b "$bus" getvcp 10 --brief 2>/dev/null || true)
  if [ -z "$reading" ]; then
    rm -f "$state_dir/ddc-$output"
    bus=$(ddc_bus_for "$output") || {
      osd_message "No DDC/CI brightness on this display"
      die "no DDC/CI display for $output"
    }
    reading=$("$ddcutil" -b "$bus" getvcp 10 --brief 2>/dev/null || true)
  fi
  read -r _ _ _ current max <<<"$reading"
  [ -n "${max:-}" ] || {
    osd_message "Could not read brightness from this display"
    die "could not read brightness from $output"
  }

  case "$action" in
    up) target=$((current + step)) ;;
    down) target=$((current - step)) ;;
    set) target=$step ;;
    max) target=$max ;;
    min) target=1 ;;
    show)
      printf '%s %s/%s\n' "$output" "$current" "$max"
      return 0
      ;;
    *) die "brightness takes up, down, set N, max, min, or show" ;;
  esac

  [ "$target" -lt 1 ] && target=1
  [ "$target" -gt "$max" ] && target=$max
  "$ddcutil" -b "$bus" setvcp 10 "$target" >/dev/null || {
    osd_message "Could not set brightness on this display"
    die "could not set brightness on $output"
  }

  # Internal panels get their OSD from the sysfs watcher. An external display
  # has no watched file, so ask the shell directly.
  "$quickshell" ipc call osd payload \
    "{\"icon\":\"brightness\",\"value\":$target,\"max\":$max}" >/dev/null 2>&1 || true
  printf '%s %s/%s\n' "$output" "$target" "$max"
}

brightness_action() {
  local action="${1:-show}" step="${2:-5}" name
  name=$(focused_name)
  [ -n "$name" ] || die "no focused monitor"

  if internal_output "$name"; then
    brightness_internal "$action" "$step"
  else
    brightness_external "$name" "$action" "$step"
  fi
}

# The base workspace of a monitor's 1-10 block. A monitor with no saved block
# starts at 1, which keeps a single-screen machine working before the first
# sync has run.
