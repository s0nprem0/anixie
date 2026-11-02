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
  sdrbrightness=1
  sdrsaturation=1

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
    saved=$(awk -v n="$name" '$1 == n { print $2, $3, $4, $5, $6, $7, $8, $9 }' "$state_file")
    if [ -n "$saved" ]; then
      read -r s_scale s_transform s_disabled s_mirror s_position s_mode s_sdrbrightness s_sdrsaturation <<<"$saved"
      [ -n "$s_scale" ] && scale="$s_scale"
      [ -n "$s_transform" ] && transform="$s_transform"
      [ -n "$s_disabled" ] && disabled="$s_disabled"
      [ -n "$s_mirror" ] && mirror="$s_mirror"
      [ -n "$s_position" ] && position="$s_position"
      [ -n "$s_mode" ] && mode="$s_mode"
      [ -n "$s_sdrbrightness" ] && sdrbrightness="$s_sdrbrightness"
      [ -n "$s_sdrsaturation" ] && sdrsaturation="$s_sdrsaturation"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$scale" "$transform" "$disabled" "$mirror" "$position" "$mode" "$sdrbrightness" "$sdrsaturation"
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
  read -r scale transform disabled mirror position mode sdrbrightness sdrsaturation <<<"$state"
  case "$disabled" in 1 | true) disabled=true ;; *) disabled=false ;; esac

  case "$key" in
    scale) scale="$value" ;;
    transform) transform="$value" ;;
    disabled) disabled="$value" ;;
    mirror) mirror="$value" ;;
    position) position="$value" ;;
    mode) mode="$value" ;;
    sdrbrightness) sdrbrightness="$value" ;;
    sdrsaturation) sdrsaturation="$value" ;;
    *) die "unknown monitor setting \"$key\"" ;;
  esac

  [ "$mirror" = none ] && mirror=""
  rule="hl.monitor({ output = \"$output\", mode = \"$mode\", position = \"$position\", scale = $scale, transform = $transform, disabled = $disabled, mirror = \"$mirror\", sdrbrightness = $sdrbrightness, sdrsaturation = $sdrsaturation })"
  "$hyprctl" eval "$rule" >/dev/null
}

# Every output, as a JSON array the panel renders as one row each. The mode list
# is stripped of ddcutil/hyprctl's "Hz" suffix because hl.monitor wants the bare
# rate when a mode is written back.
