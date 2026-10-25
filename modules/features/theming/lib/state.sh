#!/bin/sh

: "${STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/anixie/theme}"
: "${JQ:=jq}"
: "${FLOCK:=flock}"

state_file="$STATE_DIR/state.json"
state_legacy_current="$STATE_DIR/current"

state_migrate() {
  if [ -s "$state_file" ]; then
    if "$JQ" -e 'type == "object" and .version == 1' "$state_file" >/dev/null 2>&1; then
      return 0
    fi
    mv "$state_file" "$state_file.bad" || return 1
  fi

  mkdir -p "$STATE_DIR" || return 1

  state_theme=""
  if [ -f "$state_legacy_current" ]; then
    state_theme=$(tr -d '[:space:]' <"$state_legacy_current")
  fi
  [ -n "$state_theme" ] || state_theme="${DEFAULT_THEME:-tokyo-night}"

  state_source=preset
  state_follow=false
  if [ "$state_theme" = wallpaper ]; then
    state_source=wallpaper
    state_follow=true
  fi

  state_tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  if "$JQ" -n \
    --arg theme "$state_theme" \
    --arg source "$state_source" \
    --argjson follow "$state_follow" \
    --arg light "${AUTO_LIGHT:-07:00}" \
    --arg dark "${AUTO_DARK:-19:00}" \
    '{
      version: 1,
      source: $source,
      theme: $theme,
      followWallpaper: $follow,
      favorites: [],
      recent: [$theme],
      auto: {
        schedule: {
          enabled: false,
          light: ($light // "07:00"),
          dark: ($dark // "19:00")
        },
        rotation: { enabled: false, interval: "30m", shuffle: true }
      },
      generation: ""
    }' >"$state_tmp"; then
    mv "$state_tmp" "$state_file"
  else
    rm -f "$state_tmp"
    return 1
  fi
}

state_ensure() {
  if [ -s "$state_file" ] && "$JQ" -e 'type == "object" and .version == 1' "$state_file" >/dev/null 2>&1; then
    return 0
  fi
  state_migrate
}

state_write() {
  state_tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  if cat >"$state_tmp"; then
    mv "$state_tmp" "$state_file"
  else
    rm -f "$state_tmp"
    return 1
  fi
}

state_json() {
  state_ensure || return 1
  "$JQ" '.' "$state_file"
}

state_set_theme() {
  state_name=$1
  state_source=${2:-preset}
  state_ensure || return 1

  state_tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  if "$JQ" \
    --arg theme "$state_name" \
    --arg source "$state_source" \
    '.version = 1
     | .source = $source
     | .theme = $theme
     | .followWallpaper = ($source == "wallpaper")
     | .recent = (([$theme] + ((.recent // []) | map(select(. != $theme)))) | .[0:10])' \
    "$state_file" >"$state_tmp"; then
    mv "$state_tmp" "$state_file"
  else
    rm -f "$state_tmp"
    return 1
  fi
}

state_set_generation() {
  state_generation=$1
  state_ensure || return 1

  state_tmp=$(mktemp "$STATE_DIR/.state.XXXXXX") || return 1
  if "$JQ" --arg generation "$state_generation" '.version = 1 | .generation = $generation' \
    "$state_file" >"$state_tmp"; then
    mv "$state_tmp" "$state_file"
  else
    rm -f "$state_tmp"
    return 1
  fi
}

state_lock() {
  mkdir -p "$STATE_DIR" || return 1
  exec 9>"$STATE_DIR/.lock" || return 1
  "$FLOCK" -w 30 9 || return 1
}

state_unlock() {
  "$FLOCK" -u 9 2>/dev/null || true
  exec 9>&-
}
