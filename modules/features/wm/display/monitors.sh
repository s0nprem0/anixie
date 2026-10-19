#!/bin/bash
# Monitor control for what the brightness and function keys do not cover.
#
#   monitors scale [up|down|set N|reset]   step the focused monitor's scale
#   monitors internal [on|off|toggle]      the laptop panel's power
#   monitors mirror [on|off|toggle]        mirror the laptop onto an external
#   monitors list                         every output as JSON, for the panel
#   monitors set OUTPUT scale VALUE        one output's scale
#   monitors set OUTPUT transform VALUE    rotation and flipping
#   monitors set OUTPUT disabled yes|no    turn one output off or on
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
# The chosen values are written to a state file that features/wm/hyprland/lua.nix
# reads when it loads, so they survive a config reload and a reboot instead of
# snapping back. There is nowhere else to keep them: `hyprctl keyword` is refused
# by the Lua config manager — "keyword can't work with non-legacy parsers" — and
# Hyprland has no runtime monitor dispatcher. `hl.monitor` through `hyprctl eval`
# is the only way in, and it remembers nothing by itself.

# Every jq program below is single-quoted on purpose: they are jq, not shell, and
# $n / $k are jq's own variables rather than the shell expanding anything.
# shellcheck disable=SC2016

set -uo pipefail

hyprctl="@HYPRCTL@"
jq="@JQ@"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/anixie"
state_file="$state_dir/display.conf"

# The ladder, as words so membership can be tested with `case` rather than a float
# comparison bash cannot do.
ladder="1 1.25 1.6 2 3 4"

# Rotation, as Hyprland numbers them. hl.monitor takes the index into this list,
# not the degrees, and rejects a transform above its own maximum — so these are
# the names to show and the indices to send.
transform_names="normal 90 180 270 flipped flipped-90 flipped-180 flipped-270"

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

die() {
  printf 'monitors: %s\n' "$1" >&2
  exit 1
}

monitors_json() { "$hyprctl" monitors -j; }

focused_name() {
  "$jq" -r '[.[] | select(.focused == true)][0].name // empty' <<<"$(monitors_json)"
}

# The internal panel is the eDP one on a laptop. Falling back to the first monitor
# keeps the command doing something sensible on a desktop, where "the internal
# panel" is whichever screen came up first.
internal_name() {
  local name
  name=$("$jq" -r '[.[] | select(.name | test("^eDP"))][0].name // empty' <<<"$(monitors_json)")
  [ -n "$name" ] || name=$("$jq" -r '.[0].name // empty' <<<"$(monitors_json)")
  printf '%s' "$name"
}

# The first monitor that is not the internal one.
external_name() {
  "$jq" -r '[.[] | select((.name | test("^eDP")) | not)][0].name // empty' <<<"$(monitors_json)"
}

scale_of() {
  "$jq" -r --arg n "$1" '.[] | select(.name == $n) | .scale' <<<"$(monitors_json)"
}

# hl.monitor through eval: the only way to change a scale at runtime, and the reason
# the choice has to be persisted by hand. `mode = "preferred"` and `position = "auto"`
# are restated because a monitor rule replaces the one before it rather than merging
# with it, so leaving them out would drop the output back to Hyprland's defaults.
apply_scale() {
  "$hyprctl" eval "hl.monitor({ output = \"$1\", mode = \"preferred\", position = \"auto\", scale = $2 })" >/dev/null
}

# A monitor's current scale, transform and whether it is on, as a JSON object —
# what the Displays panel binds each row to.
monitor_fields() {
  "$jq" -c --arg n "$1" '
    .[] | select(.name == $n)
    | { name, scale, transform, disabled,
        width, height, description, focused, x, y, refreshRate }' <<<"$(monitors_json)"
}

# A monitor's field as a bare value.
field_of() {
  "$jq" -r --arg n "$1" --arg k "$2" '.[] | select(.name == $n) | .[$k]' <<<"$(monitors_json)"
}

# Every output, as a JSON array the panel renders as one row each.
list_action() {
  "$jq" '[.[] | { name, description, width, height, scale, transform, disabled, focused, x, y, refreshRate }]' <<<"$(monitors_json)"
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
# The line is `name scale transform disabled`; transform is the index and disabled
# is 0/1. Written through a temp file and renamed, so a failure part-way cannot
# leave a truncated file the config would read as "nothing saved" and reset all of
# it.
save_field() {
  local name="$1" key="$2" value="$3" tmp scale transform disabled
  mkdir -p "$state_dir" || die "could not create $state_dir"

  scale=1; transform=0; disabled=0
  if [ -f "$state_file" ]; then
    # Keep the other three fields of this output's existing line; only the one
    # being changed is replaced. A line with the old two-field shape still reads,
    # with the two new fields at their defaults.
    read -r scale transform disabled <<<"$(awk -v n="$name" '$1 == n { print ($2 == "" ? 1 : $2), ($3 == "" ? 0 : $3), ($4 == "" ? 0 : $4) }' "$state_file")"
  fi

  case "$key" in
    scale) scale="$value" ;;
    transform) transform="$value" ;;
    disabled) disabled="$value" ;;
    *) die "unknown monitor setting \"$key\"" ;;
  esac

  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  if [ -f "$state_file" ]; then
    awk -v n="$name" '$1 != n' "$state_file" >"$tmp"
  fi
  printf '%s %s %s %s\n' "$name" "$scale" "$transform" "$disabled" >>"$tmp"
  mv "$tmp" "$state_file"
}

forget_scale() {
  local name="$1" tmp
  [ -f "$state_file" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  awk -v n="$name" '$1 != n' "$state_file" >"$tmp"
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
      apply_scale "$name" "$target"
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
      apply_scale "$name" "$target"
      save_field "$name" scale "$target"
      printf '%s at %sx\n' "$name" "$target"
      ;;
    reset)
      name=$(focused_name)
      [ -n "$name" ] || die "no focused monitor"
      forget_scale "$name"
      apply_scale "$name" 1
      printf '%s back to 1x\n' "$name"
      ;;
    *)
      die "scale takes up, down, set N, reset, or nothing to show the current one"
      ;;
  esac
}

internal_action() {
  local action="${1:-toggle}" name
  case "$action" in
    on | off | toggle) ;;
    *) die "internal takes on, off or toggle" ;;
  esac

  name=$(internal_name)
  [ -n "$name" ] || die "no monitor found"

  # hl.dsp.dpms, because `hyprctl dispatch dpms` would be read as Lua by the config
  # manager and there is no classic dispatcher left to fall back on.
  "$hyprctl" eval "hl.dispatch(hl.dsp.dpms({ monitor = \"$name\", action = \"$action\" }))" >/dev/null
  printf 'internal panel %s: %s\n' "$name" "$action"
}

mirror_action() {
  local action="${1:-toggle}" internal external mirrored
  internal=$(internal_name)
  external=$(external_name)

  [ -n "$external" ] || die "no external monitor connected to mirror onto"

  # Read rather than remembered: `mirrorOf` on the external is Hyprland's own answer,
  # so the toggle cannot drift out of step with a mirror set some other way.
  mirrored=$("$jq" -r --arg n "$external" '.[] | select(.name == $n) | (.mirrorOf // "none")' <<<"$(monitors_json)")

  case "$action" in
    toggle)
      if [ "$mirrored" = "none" ]; then action="on"; else action="off"; fi
      ;;
    on | off) ;;
    *) die "mirror takes on, off or toggle" ;;
  esac

  if [ "$action" = "on" ]; then
    "$hyprctl" eval "hl.monitor({ output = \"$external\", mode = \"preferred\", position = \"auto\", scale = 1, mirror = \"$internal\" })" >/dev/null
    printf '%s now mirrors %s\n' "$external" "$internal"
  else
    # An empty mirror target is how a monitor rule says "not mirroring".
    "$hyprctl" eval "hl.monitor({ output = \"$external\", mode = \"preferred\", position = \"auto\", scale = 1, mirror = \"\" })" >/dev/null
    printf '%s extended again\n' "$external"
  fi
}

status_action() {
  "$jq" -r '.[] | "\(.name)\t\(.width)x\(.height)\tscale \(.scale)\t\(if (.mirrorOf // "none") == "none" then "extended" else "mirror of \(.mirrorOf)" end)\(if .focused then "\tfocused" else "" end)"' <<<"$(monitors_json)"
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

  local index
  case "$key" in
    scale)
      case " $ladder " in
        *" $value "*) ;;
        *) die "scale must be one of: $ladder" ;;
      esac
      apply_scale "$output" "$value"
      save_field "$output" scale "$value"
      ;;
    transform)
      index=$(transform_index "$value") ||
        die "transform must be one of: $transform_names"
      "$hyprctl" eval "hl.monitor({ output = \"$output\", mode = \"preferred\", position = \"auto\", scale = $(field_of "$output" scale), transform = $index })" >/dev/null
      save_field "$output" transform "$index"
      ;;
    disabled)
      case "$value" in
        yes | true | on) index=1 ;;
        no | false | off) index=0 ;;
        *) die "disabled takes yes or no" ;;
      esac
      "$hyprctl" eval "hl.monitor({ output = \"$output\", mode = \"preferred\", position = \"auto\", scale = $(field_of "$output" scale), disabled = $([ "$index" = 1 ] && echo true || echo false) })" >/dev/null
      save_field "$output" disabled "$index"
      ;;
    *)
      die "set takes scale, transform or disabled"
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
  mirror)
    shift
    mirror_action "${1:-toggle}"
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
