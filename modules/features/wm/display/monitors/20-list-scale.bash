list_action() {
  # Hyprland names the mirror target by monitor id, so an unedited `mirrorOf`
  # reaches the panel as "0" and reads as a bug on screen. Resolve it against
  # the same snapshot; a value that is already a name is passed through.
  #
  # The saved position and mode are not in Hyprland's answer — they exist only
  # in the state file — but the panel needs them to show what was chosen
  # ("Preferred", "Left of others") rather than only what it resolved to.
  "$jq" --arg state "$(cat "$state_file" 2>/dev/null || true)" '
    ($state | split("\n") | map(select(length > 0) | split(" "))
      | map({ key: .[0], value: {
          position: (.[5] // "auto"),
          mode: (.[6] // "preferred")
        } })
      | from_entries) as $saved
    | . as $all
    | ($all | map({ key: (.id | tostring), value: .name }) | from_entries) as $names
    | $all | map({
        name, description, width, height, scale, transform, disabled, focused,
        x, y, refreshRate, colorManagementPreset,
        mirrorOf: (if (.mirrorOf // "none") == "none" or (.mirrorOf // "") == ""
          then "none" else ($names[.mirrorOf] // .mirrorOf) end),
        savedPosition: ($saved[.name].position // "auto"),
        savedMode: ($saved[.name].mode // "preferred"),
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
  read -r scale transform disabled mirror position mode sdrbrightness sdrsaturation <<<"$state"

  case "$key" in
    scale) scale="$value" ;;
    transform) transform="$value" ;;
    disabled) disabled="$value" ;;
    mirror) mirror="${value:-none}" ;;
    position) position="${value:-auto}" ;;
    mode) mode="${value:-preferred}" ;;
    sdrbrightness) sdrbrightness="$value" ;;
    sdrsaturation) sdrsaturation="$value" ;;
    *) die "unknown monitor setting \"$key\"" ;;
  esac

  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  if [ -f "$state_file" ]; then
    awk -v n="$name" '$1 != n' "$state_file" >"$tmp"
  fi
  printf '%s %s %s %s %s %s %s %s %s\n' "$name" "$scale" "$transform" "$disabled" "$mirror" "$position" "$mode" "$sdrbrightness" "$sdrsaturation" >>"$tmp"
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

