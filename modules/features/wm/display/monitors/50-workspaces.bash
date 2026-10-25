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
