#!/bin/bash
# Monitor control for what the brightness and function keys do not cover.
#
#   monitors scale [up|down|set N|reset]   step the focused monitor's scale
#   monitors internal [on|off|toggle]      the laptop panel's power
#   monitors lid [close|open|toggle|reconcile]
#                                          clamshell handling for the lid
#   monitors mirror [on|off|toggle]        mirror the laptop onto an external
#   monitors brightness [up|down|set N|max|min] [STEP]
#                                          the focused display's backlight
#   monitors list                          every output as JSON, for the panel
#   monitors set OUTPUT scale VALUE        one output's scale
#   monitors set OUTPUT transform VALUE    rotation and flipping
#   monitors set OUTPUT disabled yes|no    turn one output off or on
#   monitors set OUTPUT position VALUE     auto, auto-left/right/up/down, XxY
#   monitors set OUTPUT mode VALUE         preferred, highres, highrr, WxH[@R]
#   monitors set OUTPUT mirror VALUE       none, or the output to mirror
#   monitors recover                       clear a stale internal-off state
#   monitors wake                          cycle DPMS on every output
#   monitors workspace N                   focus the Nth workspace of this monitor
#   monitors workspace-step next|prev      move one workspace within its block
#   monitors move-window N                 move the window to that workspace
#   monitors workspaces sync|show|reset    per-monitor workspace blocks
#   monitors status                        one line per monitor
#
# Scaling steps through 1x, 1.25x, 1.6x, 2x, 3x and 4x — the ratios worth having
# between "this is a 1080p panel" and "this is a 6K one". Only the focused monitor
# is stepped, which is what makes the keys usable with a second screen attached.
#
# `set` is the same machinery aimed at a named output rather than the focused one,
# which is what the Displays panel needs: it lists every screen and changes this
# one, and a panel that could only reach whichever was focused would be useless
# with two.
#
# The chosen values are written to a state file that
# features/wm/hyprland/config/20-settings.lua reads when it loads, so they survive
# a config reload and a reboot instead of
# snapping back. That state includes the mirror target, position and mode as
# well as scale, rotation and on/off, because a reload would otherwise
# re-apply the output's ordinary rule and quietly end a mirror or reset the
# arrangement. There is nowhere else to keep them:
# `hyprctl keyword` is refused by the Lua config manager — "keyword can't work
# with non-legacy parsers" — and Hyprland has no runtime monitor dispatcher.
# `hl.monitor` through `hyprctl eval` is the only way in, and it remembers
# nothing by itself.

# Every jq program below is single-quoted on purpose: they are jq, not shell, and
# $n / $k are jq's own variables rather than the shell expanding anything.
# shellcheck disable=SC2016

set -uo pipefail

hyprctl="@HYPRCTL@"
jq="@JQ@"
brightnessctl="@BRIGHTNESSCTL@"
ddcutil="@DDCUTIL@"
quickshell="@QUICKSHELL@"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/anixie"
state_file="$state_dir/display.conf"
lid_file="$state_dir/lid"
workspace_file="$state_dir/workspaces.json"

# The ladder, as words so membership can be tested with `case` rather than a float
# comparison bash cannot do.
ladder="1 1.25 1.6 2 3 4"

# Rotation, as Hyprland numbers them. hl.monitor takes the index into this list,
# not the degrees, and rejects a transform above its own maximum — so these are
# the names to show and the indices to send.
transform_names="normal 90 180 270 flipped flipped-90 flipped-180 flipped-270"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# Active outputs only. A disabled output cannot be focused, and it is not a
# place to mirror onto.
monitors_json() { "$hyprctl" monitors -j; }

# Every output, including the ones that are switched off. `hyprctl monitors`
# omits a disabled output entirely; using it for the panel or for `set` would
# remove the only row that could turn the screen back on.
all_monitors_json() { "$hyprctl" monitors all -j; }

focused_name() {
  "$jq" -r '[.[] | select(.focused == true)][0].name // empty' <<<"$(monitors_json)"
}

# The internal panel is the eDP one on a laptop. Falling back to the first monitor
# keeps the command doing something sensible on a desktop, where "the internal
# panel" is whichever screen came up first. Read from the full list so a panel
# switched off with `set ... disabled` is still found.
internal_name() {
  local name
  name=$("$jq" -r '[.[] | select(.name | test("^eDP"))][0].name // empty' <<<"$(all_monitors_json)")
  [ -n "$name" ] || name=$("$jq" -r '.[0].name // empty' <<<"$(all_monitors_json)")
  printf '%s' "$name"
}

# The first attached monitor that is not the internal one. Read from the full
# list: Hyprland drops a mirrored output from `monitors`, so looking only at the
# active ones makes mirroring a one-way trip — the target is still a valid
# screen to find, even while it is showing the laptop panel.
external_name() {
  "$jq" -r '[.[] | select(.disabled == false)
    | select(.name | test("^eDP|^LVDS|^DSI") | not)][0].name // empty' <<<"$(all_monitors_json)"
}

scale_of() {
  "$jq" -r --arg n "$1" '.[] | select(.name == $n) | .scale' <<<"$(all_monitors_json)"
}

# A monitor's field as a bare value. The full list, because every setting has to
# be readable from a screen that is currently off as well as one that is on.
field_of() {
  "$jq" -r --arg n "$1" --arg k "$2" '.[] | select(.name == $n) | .[$k]' <<<"$(all_monitors_json)"
}

# One output's live scale, transform, on/off, mirror and position. One read for
# all of them, so a rule is built from a consistent snapshot rather than from
# several hyprctl calls that could straddle a change.
monitor_state() {
  "$jq" -r --arg n "$1" '
    . as $all
    | ($all | map({ key: (.id | tostring), value: .name }) | from_entries) as $names
    | $all[] | select(.name == $n)
    | [.scale, .transform, .disabled,
       (if (.mirrorOf // "none") == "none" or (.mirrorOf // "") == ""
        then "none" else ($names[.mirrorOf] // .mirrorOf) end),
       "\(.x)x\(.y)"] | @tsv' <<<"$(all_monitors_json)"
}

# The effective state for one output: its saved line when there is one,
# otherwise what it is doing now plus `preferred` mode. Prints
# `scale transform disabled mirror position mode` as tab-separated fields.
#
# The saved line wins because it is what this machine chose, including for an
# output that is switched off and has no useful runtime state. Older lines have
# fewer fields; the missing ones fall back to the live values.
read_state() {
  local name="$1" live saved
  local scale transform disabled mirror position mode
  local s_scale s_transform s_disabled s_mirror s_position s_mode

  live=$(monitor_state "$name")
  [ -n "$live" ] || return 1
  read -r scale transform disabled mirror position <<<"$live"
  mode=preferred

  case "$scale" in "" | 0 | 0.0 | null) scale=1 ;; esac
  case "$transform" in "" | null) transform=0 ;; esac
  case "$disabled" in true) disabled=1 ;; *) disabled=0 ;; esac
  case "$mirror" in "" | null) mirror=none ;; esac
  case "$position" in "" | null) position=auto ;; esac
  # A disabled output's live x/y is not a layout it is using. Without a saved
  # position, let the catch-all place it when it comes back rather than pinning
  # it to a stale corner.
  [ "$disabled" = 1 ] && position=auto

  if [ -f "$state_file" ]; then
    saved=$(awk -v n="$name" '$1 == n { print $2, $3, $4, $5, $6, $7 }' "$state_file")
    if [ -n "$saved" ]; then
      read -r s_scale s_transform s_disabled s_mirror s_position s_mode <<<"$saved"
      [ -n "$s_scale" ] && scale="$s_scale"
      [ -n "$s_transform" ] && transform="$s_transform"
      [ -n "$s_disabled" ] && disabled="$s_disabled"
      [ -n "$s_mirror" ] && mirror="$s_mirror"
      [ -n "$s_position" ] && position="$s_position"
      [ -n "$s_mode" ] && mode="$s_mode"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scale" "$transform" "$disabled" "$mirror" "$position" "$mode"
}

# Apply one change while keeping the rest of the output's rule. A monitor rule
# replaces the previous one rather than merging with it, so a rule carrying only
# the field being changed would undo the rotation, switch a disabled screen back
# on, reset the arrangement, and break a mirror on every scale change.
#
# `mirror = ""` is how a rule says "not mirroring"; the full target is restated
# otherwise so changing a scale does not silently end the mirror.
apply_change() {
  local output="$1" key="$2" value="$3" state scale transform disabled mirror position mode rule

  state=$(read_state "$output") || die "no output called \"$output\""
  read -r scale transform disabled mirror position mode <<<"$state"
  case "$disabled" in 1 | true) disabled=true ;; *) disabled=false ;; esac

  case "$key" in
    scale) scale="$value" ;;
    transform) transform="$value" ;;
    disabled) disabled="$value" ;;
    mirror) mirror="$value" ;;
    position) position="$value" ;;
    mode) mode="$value" ;;
    *) die "unknown monitor setting \"$key\"" ;;
  esac

  [ "$mirror" = none ] && mirror=""
  rule="hl.monitor({ output = \"$output\", mode = \"$mode\", position = \"$position\", scale = $scale, transform = $transform, disabled = $disabled, mirror = \"$mirror\" })"
  "$hyprctl" eval "$rule" >/dev/null
}

# Every output, as a JSON array the panel renders as one row each. The mode list
# is stripped of ddcutil/hyprctl's "Hz" suffix because hl.monitor wants the bare
# rate when a mode is written back.
list_action() {
  # Hyprland names the mirror target by monitor id, so an unedited `mirrorOf`
  # reaches the panel as "0" and reads as a bug on screen. Resolve it against
  # the same snapshot; a value that is already a name is passed through.
  "$jq" '
    . as $all
    | ($all | map({ key: (.id | tostring), value: .name }) | from_entries) as $names
    | $all | map({
        name, description, width, height, scale, transform, disabled, focused,
        x, y, refreshRate,
        mirrorOf: (if (.mirrorOf // "none") == "none" or (.mirrorOf // "") == ""
          then "none" else ($names[.mirrorOf] // .mirrorOf) end),
        availableModes: [(.availableModes // [])[] | sub("Hz$"; "")] | unique
      })' <<<"$(all_monitors_json)"
}

# Read a transform's index out of the names list above.
transform_index() {
  local want="$1" i=0 name
  for name in $transform_names; do
    [ "$name" = "$want" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# Write one output's line into the state file, keeping every other output's.
# The line is `name scale transform disabled mirror position mode`; transform is
# the index, disabled is 0/1, mirror is an output name or `none`, position is
# `auto`, `auto-*` or `XxY`, and mode is `preferred` or a resolution string.
# Written through a temp file and renamed, so a failure part-way cannot leave a
# truncated file the config would read as "nothing saved" and reset all of it.
save_field() {
  local name="$1" key="$2" value="$3" tmp state
  local scale transform disabled mirror position mode
  mkdir -p "$state_dir" || die "could not create $state_dir"

  state=$(read_state "$name") || die "no output called \"$name\""
  read -r scale transform disabled mirror position mode <<<"$state"

  case "$key" in
    scale) scale="$value" ;;
    transform) transform="$value" ;;
    disabled) disabled="$value" ;;
    mirror) mirror="${value:-none}" ;;
    position) position="${value:-auto}" ;;
    mode) mode="${value:-preferred}" ;;
    *) die "unknown monitor setting \"$key\"" ;;
  esac

  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  if [ -f "$state_file" ]; then
    awk -v n="$name" '$1 != n' "$state_file" >"$tmp"
  fi
  printf '%s %s %s %s %s %s %s\n' "$name" "$scale" "$transform" "$disabled" "$mirror" "$position" "$mode" >>"$tmp"
  mv "$tmp" "$state_file"
}

# The next rung up or down. The whole ladder is passed in so the two stay in step.
#
# Down takes the last rung below the current one, not the first: a scale that sits
# between two rungs — typed by hand, or left over from a ladder that has since
# changed — still steps down rather than jumping to the bottom.
next_scale() {
  awk -v cur="$1" -v dir="$2" -v ladder="$ladder" 'BEGIN {
    n = split(ladder, rung, " ")
    best = cur
    if (dir == "up") {
      for (i = 1; i <= n; i++) if (rung[i] + 0 > cur + 0) { best = rung[i]; break }
    } else {
      for (i = 1; i <= n; i++) if (rung[i] + 0 < cur + 0) best = rung[i]
    }
    print best
  }'
}

scale_action() {
  local action="${1:-show}" name scale target

  case "$action" in
    show)
      name=$(focused_name)
      [ -n "$name" ] || die "no focused monitor"
      printf '%s %sx\n' "$name" "$(scale_of "$name")"
      ;;
    up | down)
      name=$(focused_name)
      [ -n "$name" ] || die "no focused monitor to scale"
      scale=$(scale_of "$name")
      [ -n "$scale" ] || die "could not read the scale of $name"
      target=$(next_scale "$scale" "$action")
      if [ "$target" = "$scale" ]; then
        printf '%s is already at %sx, the end of the ladder\n' "$name" "$scale"
        return 0
      fi
      apply_change "$name" scale "$target"
      save_field "$name" scale "$target"
      printf '%s at %sx\n' "$name" "$target"
      ;;
    set)
      target="${2:-}"
      [ -n "$target" ] || die "set needs a scale"
      case " $ladder " in
        *" $target "*) ;;
        *) die "scale must be one of: $ladder" ;;
      esac
      name=$(focused_name)
      [ -n "$name" ] || die "no focused monitor"
      apply_change "$name" scale "$target"
      save_field "$name" scale "$target"
      printf '%s at %sx\n' "$name" "$target"
      ;;
    reset)
      name=$(focused_name)
      [ -n "$name" ] || die "no focused monitor"
      apply_change "$name" scale 1
      save_field "$name" scale 1
      printf '%s back to 1x\n' "$name"
      ;;
    *)
      die "scale takes up, down, set N, reset, or nothing to show the current one"
      ;;
  esac
}

internal_action() {
  local action="${1:-toggle}" name disabled
  case "$action" in
    on | off | toggle) ;;
    *) die "internal takes on, off or toggle" ;;
  esac

  name=$(internal_name)
  [ -n "$name" ] || die "no monitor found"
  disabled=$(field_of "$name" disabled)

  if [ "$action" = "toggle" ]; then
    if [ "$disabled" = true ]; then action=on; else action=off; fi
  fi

  if [ "$action" = "off" ]; then
    [ "$disabled" = true ] && return 0
    [ "$(active_count)" -le 1 ] && die "refusing to disable the only active output"
    apply_change "$name" disabled true
    save_field "$name" disabled 1
    printf 'internal panel %s: off\n' "$name"
  else
    [ "$disabled" != true ] && return 0
    apply_change "$name" disabled false
    save_field "$name" disabled 0
    workspaces_sync_action >/dev/null
    printf 'internal panel %s: on\n' "$name"
  fi
}

mirror_action() {
  local action="${1:-toggle}" internal external mirrored
  internal=$(internal_name)
  external=$(external_name)

  [ -n "$external" ] || die "no external monitor connected to mirror onto"
  [ "$(field_of "$internal" disabled)" = true ] &&
    die "internal panel is off; turn it on before mirroring"

  # Read rather than remembered: `mirrorOf` on the external is Hyprland's own answer,
  # so the toggle cannot drift out of step with a mirror set some other way.
  mirrored=$(field_of "$external" mirrorOf)
  [ "$mirrored" = null ] && mirrored=none

  case "$action" in
    toggle)
      if [ "${mirrored:-none}" = "none" ]; then action="on"; else action="off"; fi
      ;;
    on | off) ;;
    *) die "mirror takes on, off or toggle" ;;
  esac

  if [ "$action" = "on" ]; then
    apply_change "$external" mirror "$internal"
    save_field "$external" mirror "$internal"
    printf '%s now mirrors %s\n' "$external" "$internal"
  else
    apply_change "$external" mirror none
    save_field "$external" mirror none
    printf '%s extended again\n' "$external"
  fi
}

status_action() {
  # Same id-to-name resolution as the panel: `mirror of 0` is Hyprland's
  # internal target id, not something a person can act on.
  "$jq" -r '
    . as $all
    | ($all | map({ key: (.id | tostring), value: .name }) | from_entries) as $names
    | $all[]
    | "\(.name)\t\(.width)x\(.height)\tscale \(.scale)\t"
      + (if .disabled then "off"
         elif (.mirrorOf // "none") == "none" or (.mirrorOf // "") == ""
         then "extended"
         else "mirror of \($names[.mirrorOf] // .mirrorOf)" end)
      + (if .focused then "\tfocused" else "" end)' <<<"$(all_monitors_json)"
}

# How many outputs are currently in the layout. A saved state can leave an
# output disabled; only the active ones count for the last-display guard.
active_count() {
  "$jq" '[.[] | select(.disabled == false)] | length' <<<"$(all_monitors_json)"
}

# Close the lid with an external attached: take the internal panel out of the
# layout, remembering that this script did it. Opening it puts the panel back at
# its saved scale/position/mode. A panel the user had already switched off is
# left alone, so this does not undo a deliberate choice.
lid_action() {
  local action="${1:-toggle}" internal external saved
  internal=$(internal_name)
  external=$(external_name)
  [ -n "$internal" ] || return 0

  case "$action" in
    close | off)
      [ -n "$external" ] || {
        printf 'no external monitor; leaving the internal panel on\n'
        return 0
      }
      [ "$(field_of "$internal" disabled)" = true ] && return 0
      apply_change "$internal" disabled true
      save_field "$internal" disabled 1
      mkdir -p "$state_dir" || die "could not create $state_dir"
      printf '%s\n' "$internal" >"$lid_file"
      printf 'lid closed: internal panel %s off\n' "$internal"
      ;;
    open | on)
      [ -f "$lid_file" ] || return 0
      saved=$(cat "$lid_file" 2>/dev/null || true)
      [ -n "$saved" ] || {
        rm -f "$lid_file"
        return 0
      }
      [ -n "$(field_of "$saved" name)" ] || {
        rm -f "$lid_file"
        return 0
      }
      apply_change "$saved" disabled false
      save_field "$saved" disabled 0
      rm -f "$lid_file"
      workspaces_sync_action >/dev/null
      printf 'lid opened: internal panel %s on\n' "$saved"
      ;;
    toggle)
      if [ -f "$lid_file" ]; then lid_action open; else lid_action close; fi
      ;;
    reconcile)
      if lid_closed && [ -n "$(external_name)" ]; then
        lid_action close
      else
        lid_action open
      fi
      ;;
    *) die "lid takes close, open, toggle or reconcile" ;;
  esac
}

# Whether the firmware reports the lid as closed. The pre-session recovery has
# no Hyprland to ask, and the switch event may not have fired yet.
lid_closed() {
  local state
  for state in /proc/acpi/button/lid/*/state; do
    [ -r "$state" ] || continue
    grep -q closed "$state" && return 0
  done
  return 1
}

# Clear the disabled flag on one output, leaving every other field alone.
clear_disabled() {
  local output="$1" tmp
  [ -f "$state_file" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  awk -v n="$output" -v OFS=' ' '
    $1 == n && $4 == "1" { $4 = "0" }
    { print }
  ' "$state_file" >"$tmp"
  if cmp -s "$state_file" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$state_file"
  fi
}

# Clear a saved "internal panel off" when no external display is connected, and
# clear a clamshell state left over from the last shutdown when the lid is open
# again. This runs before the graphical session, when Hyprland is not up yet, so
# it reads the DRM connectors and the firmware lid state directly. Without it,
# docking, switching the laptop panel off, and booting undocked would apply
# disabled = true to the only screen.
recover_action() {
  local name status lid_output
  [ -f "$state_file" ] || {
    rm -f "$lid_file"
    return 0
  }

  if [ -f "$lid_file" ] && ! lid_closed; then
    lid_output=$(cat "$lid_file" 2>/dev/null || true)
    [ -n "$lid_output" ] && clear_disabled "$lid_output"
    rm -f "$lid_file"
    printf 'lid is open; cleared the saved clamshell state\n'
  fi

  for status in /sys/class/drm/card*-*/status; do
    [ -r "$status" ] || continue
    [ "$(cat "$status")" = connected ] || continue
    name=${status%/status}
    # A connected connector with no EDID is not a display the kernel can mode;
    # treating it as usable would keep the internal panel off for a screen that
    # will come up at 0x0. `-s` is not enough here: sysfs reports the edid
    # attribute's stat size as 0 even when reading it returns the blob.
    [ "$(wc -c <"$name/edid" 2>/dev/null || printf 0)" -gt 0 ] || continue
    name=${name##*/}
    name=${name#card*-}
    case "$name" in
      eDP* | LVDS* | DSI* | Virtual* | HEADLESS*) ;;
      *)
        printf 'external display %s is connected; keeping the saved state\n' "$name"
        return 0
        ;;
    esac
  done

  # No usable external display: clear every internal panel that was left off,
  # and drop the lid marker so opening the lid later does not try to restore a
  # panel that is already on.
  for name in $(awk '$1 ~ /^(eDP|LVDS|DSI)/ && $4 == "1" { print $1 }' "$state_file"); do
    clear_disabled "$name"
  done
  rm -f "$lid_file"
  printf 'no external display; cleared the internal-display off state\n'
}

# Cycle DPMS off and on. Hyprland does not always repaint a panel after resume;
# a full off/on cycle is the reliable way to bring it back without a VT switch.
wake_action() {
  "$hyprctl" eval 'hl.dispatch(hl.dsp.dpms({ action = "off" }))' >/dev/null
  sleep 0.2
  "$hyprctl" eval 'hl.dispatch(hl.dsp.dpms({ action = "on" }))' >/dev/null
  printf 'display power cycled\n'
}

# The internal panel is the one with a kernel backlight; everything else is
# adjusted over DDC/CI. The name test matches the eDP/LVDS/DSI panels the kernel
# and Hyprland use.
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
workspace_base() {
  local name="$1" base
  [ -f "$workspace_file" ] || {
    printf '1'
    return 0
  }
  base=$("$jq" -r --arg n "$name" '.[$n] // empty' "$workspace_file" 2>/dev/null || true)
  [ -n "$base" ] || base=1
  printf '%s' "$base"
}

# Give every active monitor a block of ten workspaces, keeping blocks for
# outputs that are not connected right now so a dock gets the same numbers back.
# The mapping is written to workspaces.json for the bar, and the workspace rules
# are re-asserted through Hyprland's Lua API.
workspaces_sync_action() {
  local map names name base candidate i lua tmp
  map='{}'
  if [ -f "$workspace_file" ]; then
    map=$(cat "$workspace_file" 2>/dev/null || printf '{}')
    "$jq" -e 'type == "object"' <<<"$map" >/dev/null 2>&1 || map='{}'
  fi

  names=$("$jq" -r '.[].name' <<<"$(monitors_json)")
  for name in $names; do
    if [ "$("$jq" -r --arg n "$name" 'has($n)' <<<"$map")" != true ]; then
      candidate=1
      while [ "$("$jq" -r --argjson b "$candidate" 'any(.[]; . == $b)' <<<"$map")" = true ]; do
        candidate=$((candidate + 10))
      done
      map=$("$jq" --arg n "$name" --argjson b "$candidate" '. + {($n): $b}' <<<"$map")
    fi
  done

  mkdir -p "$state_dir" || die "could not create $state_dir"
  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  "$jq" -S . <<<"$map" >"$tmp"
  mv "$tmp" "$workspace_file"

  lua=""
  for name in $names; do
    base=$("$jq" -r --arg n "$name" '.[$n]' <<<"$map")
    i=1
    while [ "$i" -le 10 ]; do
      if [ "$i" = 1 ]; then
        lua+="hl.workspace_rule({ workspace = \"$base\", monitor = \"$name\", default = true }); "
      else
        lua+="hl.workspace_rule({ workspace = \"$((base + i - 1))\", monitor = \"$name\" }); "
      fi
      i=$((i + 1))
    done
  done
  [ -n "$lua" ] && "$hyprctl" eval "$lua" >/dev/null
  printf '%s\n' "$map"
}

workspaces_action() {
  local action="${1:-sync}"
  case "$action" in
    sync) workspaces_sync_action ;;
    show)
      if [ -f "$workspace_file" ]; then
        "$jq" -S . "$workspace_file"
      else
        printf '{}\n'
      fi
      ;;
    reset)
      rm -f "$workspace_file"
      workspaces_sync_action
      ;;
    *) die "workspaces takes sync, show or reset" ;;
  esac
}

workspace_action() {
  local slot="${1:-}" name base id
  [ -n "$slot" ] || die "workspace needs a number"
  case "$slot" in
    *[!0-9]*) die "workspace needs a number" ;;
  esac
  [ "$slot" -ge 1 ] && [ "$slot" -le 10 ] || die "workspace must be 1-10"
  name=$(focused_name)
  [ -n "$name" ] || die "no focused monitor"
  base=$(workspace_base "$name")
  id=$((base + slot - 1))
  "$hyprctl" eval "hl.dispatch(hl.dsp.focus({ workspace = \"$id\" }))" >/dev/null
  printf '%s workspace %s (global %s)\n' "$name" "$slot" "$id"
}

workspace_step_action() {
  local direction="${1:-next}" name base current target
  case "$direction" in
    next | prev) ;;
    *) die "workspace-step takes next or prev" ;;
  esac
  name=$(focused_name)
  [ -n "$name" ] || die "no focused monitor"
  base=$(workspace_base "$name")
  current=$("$jq" -r '.[] | select(.focused == true) | .activeWorkspace.id' <<<"$(monitors_json)")
  [ -n "$current" ] && [ "$current" != null ] || return 0

  if [ "$direction" = "next" ]; then
    target=$((current + 1))
  else
    target=$((current - 1))
  fi
  [ "$target" -lt "$base" ] && target=$base
  [ "$target" -gt "$((base + 9))" ] && target=$((base + 9))

  [ "$target" = "$current" ] && return 0
  "$hyprctl" eval "hl.dispatch(hl.dsp.focus({ workspace = \"$target\" }))" >/dev/null
}

move_window_action() {
  local slot="${1:-}" name base id
  [ -n "$slot" ] || die "move-window needs a number"
  case "$slot" in
    *[!0-9]*) die "move-window needs a number" ;;
  esac
  [ "$slot" -ge 1 ] && [ "$slot" -le 10 ] || die "move-window must be 1-10"
  name=$(focused_name)
  [ -n "$name" ] || die "no focused monitor"
  base=$(workspace_base "$name")
  id=$((base + slot - 1))
  "$hyprctl" eval "hl.dispatch(hl.dsp.window.move({ workspace = \"$id\" }))" >/dev/null
  printf 'window to %s workspace %s (global %s)\n' "$name" "$slot" "$id"
}

# One output, one setting, from the panel. Applied through hl.monitor like the
# keys do — there is no other way in — and then written to the state file so it
# outlives the session.
set_action() {
  local output="${1:-}" key="${2:-}" value="${3:-}"
  [ -n "$output" ] && [ -n "$key" ] && [ -n "$value" ] ||
    die "set needs an output, a setting and a value"

  # Refuse an output that is not attached, rather than silently adding a monitor
  # rule for a name that will never come back.
  [ -n "$(field_of "$output" name)" ] || die "no output called \"$output\""

  local index disabled
  case "$key" in
    scale)
      case " $ladder " in
        *" $value "*) ;;
        *) die "scale must be one of: $ladder" ;;
      esac
      apply_change "$output" scale "$value"
      save_field "$output" scale "$value"
      ;;
    transform)
      index=$(transform_index "$value") ||
        die "transform must be one of: $transform_names"
      apply_change "$output" transform "$index"
      save_field "$output" transform "$index"
      ;;
    disabled)
      case "$value" in
        yes | true | on) index=1; disabled=true ;;
        no | false | off) index=0; disabled=false ;;
        *) die "disabled takes yes or no" ;;
      esac
      # The panel already refuses the focused screen. The CLI has no such
      # context, so it needs the stronger rule: never remove the last output.
      if [ "$index" = 1 ] && [ "$(field_of "$output" disabled)" != true ] &&
        [ "$(active_count)" -le 1 ]; then
        die "refusing to disable the only active output"
      fi
      apply_change "$output" disabled "$disabled"
      save_field "$output" disabled "$index"
      # Re-enabling adds an output back to the active set; its workspace block
      # needs the rules re-asserted because no hotplug event may arrive.
      [ "$index" = 0 ] && workspaces_sync_action >/dev/null
      ;;
    position)
      case "$value" in
        auto | auto-left | auto-right | auto-up | auto-down) ;;
        *)
          [[ "$value" =~ ^-?[0-9]+x-?[0-9]+$ ]] ||
            die "position must be auto, auto-left/right/up/down, or XxY"
          ;;
      esac
      apply_change "$output" position "$value"
      save_field "$output" position "$value"
      ;;
    mode)
      value=${value%Hz}
      case "$value" in
        preferred | highres | highrr | maxwidth) ;;
        *)
          [[ "$value" =~ ^[0-9]+x[0-9]+(@[0-9.]+)?$ ]] ||
            die "mode must be preferred, highres, highrr, or WxH[@R]"
          ;;
      esac
      apply_change "$output" mode "$value"
      save_field "$output" mode "$value"
      ;;
    mirror)
      case "$value" in
        none | off | "") value=none ;;
        *)
          [ "$value" = "$output" ] && die "an output cannot mirror itself"
          [ -n "$(field_of "$value" name)" ] ||
            die "no output called \"$value\" to mirror"
          [ "$(field_of "$value" disabled)" = true ] &&
            die "$value is off; turn it on before mirroring"
          ;;
      esac
      [ "$(field_of "$output" disabled)" = true ] &&
        die "$output is off; turn it on before mirroring"
      apply_change "$output" mirror "$value"
      save_field "$output" mirror "$value"
      # Coming back to extended gives the output a workspace again, and no
      # hotplug event arrives for a mirror being turned off.
      [ "$value" = none ] && workspaces_sync_action >/dev/null
      ;;
    *)
      die "set takes scale, transform, disabled, position, mode or mirror"
      ;;
  esac

  printf '%s %s %s\n' "$output" "$key" "$value"
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  scale)
    shift
    scale_action "${1:-show}" "${2:-}"
    ;;
  internal)
    shift
    internal_action "${1:-toggle}"
    ;;
  lid)
    shift
    lid_action "${1:-toggle}"
    ;;
  mirror)
    shift
    mirror_action "${1:-toggle}"
    ;;
  brightness)
    shift
    brightness_action "${1:-show}" "${2:-5}"
    ;;
  recover)
    recover_action
    ;;
  wake)
    wake_action
    ;;
  workspace)
    shift
    workspace_action "${1:-}"
    ;;
  workspace-step)
    shift
    workspace_step_action "${1:-next}"
    ;;
  move-window)
    shift
    move_window_action "${1:-}"
    ;;
  workspaces)
    shift
    workspaces_action "${1:-sync}"
    ;;
  list)
    list_action
    ;;
  set)
    shift
    set_action "$@"
    ;;
  status)
    status_action
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    printf 'monitors: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
