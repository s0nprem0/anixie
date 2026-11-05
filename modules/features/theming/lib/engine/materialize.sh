#!/bin/bash
# Theme materialization logic
# shellcheck disable=SC2154
# Sourced by theme.sh, which defines the tools and state directories these
# functions use; checked standalone, shellcheck cannot see those assignments.

prune_generations() {
  local current="$1" keep=0 gen line
  find "$generations_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null |
    sort -nr |
    while IFS= read -r line; do
      gen=${line#* }
      [ "$gen" = "$current" ] && continue
      keep=$((keep + 1))
      [ "$keep" -le 2 ] && continue
      rm -rf -- "$gen"
    done
}

materialise() {
  local name="$1" gen mode_value source
  mkdir -p "$state_dir" "$generations_dir" || die "could not create $state_dir"
  state_ensure || die "could not initialise $state_dir/state.json"

  if [ "$name" = "wallpaper" ]; then
    wallpaper_palette || die "the generated palette is missing; run 'theme wallpaper FILE'"
  else
    "$jq" -e --arg n "$name" '.[$n] | type == "object"' "$palettes" >/dev/null 2>&1 \
      || die "no such theme: $name"
    local tmp
    tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
    "$jq" --arg n "$name" '.[$n] | with_entries(select(.key | startswith("_") | not))' "$palettes" >"$tmp" \
      || die "could not resolve $name"
    palette_ok "$tmp" || die "theme $name is missing colours"
    mv "$tmp" "$generated"
  fi

  if [ "$name" = "wallpaper" ]; then
    mode_value=$("$jq" -r '._mode // "dark"' "$generated")
  else
    mode_value=$("$jq" -r --arg n "$name" '.[$n]._mode // "dark"' "$palettes")
  fi
  printf '%s\n' "$mode_value" | write_atomic "$state_dir/mode" \
    || die "could not write $state_dir/mode"

  gen=$(mktemp -d "$generations_dir/$(date +%Y%m%d%H%M%S)-XXXXXX") \
    || die "could not create a generation directory"
  if ! cp "$generated" "$gen/palette.json"; then
    rm -rf "$gen"
    die "could not stage the palette"
  fi
  printf '%s\n' "$mode_value" >"$gen/mode" || {
    rm -rf "$gen"
    die "could not stage the mode"
  }

  if ! write_kitty_conf "$gen/kitty.conf"; then
    rm -rf "$gen"
    die "could not write the terminal palette"
  fi
  # Record what produced this generation. `theme apply` at login can then skip
  # re-rendering an identical generation, while still regenerating after a
  # rebuild changes the palettes or the renderer.
  if ! printf '%s %s\n' "$palettes" "@THEME_APPS@" >"$gen/renderer"; then
    rm -rf "$gen"
    die "could not record the renderer"
  fi
  if ! "@THEME_APPS@" "$name" "$gen" >/dev/null 2>&1; then
    rm -rf "$gen"
    die "could not render the application themes"
  fi

  for source in palette.json mode kitty.conf helix.toml yazi.toml hyprlock.conf \
    qt6ct-colors.conf qt6ct.conf qt5ct.conf kvantum.kvconfig gtk-3.0-settings.ini gtk-4.0-settings.ini \
    gtk-3.0.css gtk-4.0.css share-picker.css discord.css tmux.conf btop.theme terminal.zsh; do
    [ -s "$gen/$source" ] || {
      rm -rf "$gen"
      die "the generation is missing $source"
    }
  done

  rm -f "$state_dir/.live.$$"
  if ! ln -s "$gen" "$state_dir/.live.$$" || ! mv -T "$state_dir/.live.$$" "$live_link"; then
    rm -rf "$gen" "$state_dir/.live.$$"
    die "could not activate the generation"
  fi

  if [ "$name" = "wallpaper" ]; then
    state_source=wallpaper
  else
    state_source=preset
  fi
  printf '%s\n' "$name" | write_atomic "$current_file" \
    || die "could not write $current_file"
  state_set_theme "$name" "$state_source" \
    || die "could not write $state_dir/state.json"
  state_set_generation "$(basename "$gen")" \
    || printf 'theme: could not record the new generation\n' >&2

  prune_generations "$gen"
}

set_theme() {
  local name="$1"
  has "$name" || die "no theme called \"$name\" (try: theme list)"
  state_lock || die "could not lock the theme state"
  materialise "$name"
  state_unlock
  tell_apps "$name"
  run_hooks "$name"
  printf 'Theme: %s\n' "$name"
}
