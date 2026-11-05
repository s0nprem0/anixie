#!/bin/bash
# Core theming engine utilities
# shellcheck disable=SC2154
# Sourced by theme.sh, which defines the tools and state directories these
# functions use; checked standalone, shellcheck cannot see those assignments.

# Write a file through a temporary in the same directory, so a failure never
# leaves a half-written palette or config behind.
write_atomic() {
  local file="$1" tmp
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if cat >"$tmp"; then
    if mv "$tmp" "$file"; then
      return 0
    fi
    rm -f "$tmp"
    return 1
  else
    rm -f "$tmp"
    return 1
  fi
}

names() {
  "$jq" -r 'keys[]' "$palettes" | sort
}

# A square swatch for the picker: background, surface, primary and accent in
# four quadrants. Cached under the state directory and regenerated when the
# palette file changes.
preview_dir="$state_dir/previews"

palette_colour() {
  "$jq" -r --arg n "$1" --arg k "$2" '.[$n][$k]' "$palettes"
}

theme_preview() {
  local name="$1" preview="$preview_dir/$1.png"
  mkdir -p "$preview_dir" || return 1
  if [ -f "$preview" ] && [ ! "$palettes" -nt "$preview" ]; then
    printf '%s' "$preview"
    return 0
  fi

  local bg surface primary accent
  bg=$(palette_colour "$name" background) || return 1
  surface=$(palette_colour "$name" surface) || return 1
  primary=$(palette_colour "$name" primary) || return 1
  accent=$(palette_colour "$name" accent) || return 1

  "$magick" -size 64x64 "xc:$bg" \
    -fill "$surface" -draw 'rectangle 0,0 31,31' \
    -fill "$primary" -draw 'rectangle 32,0 63,31' \
    -fill "$accent" -draw 'rectangle 0,32 31,63' \
    -fill "$bg" -draw 'rectangle 32,32 63,63' \
    "$preview" >/dev/null 2>&1 || return 1
  printf '%s' "$preview"
}

has() {
  # `wallpaper` is not in the file: it is whatever matugen last made of the
  # current picture, and it exists once a palette has been generated.
  [ "$1" = "wallpaper" ] && return 0
  "$jq" -e --arg n "$1" 'has($n)' "$palettes" >/dev/null 2>&1
}

mode_of() {
  "$jq" -r --arg n "$1" '.[$n]._mode // "dark"' "$palettes"
}

current_mode() {
  if [ "$(current)" = "wallpaper" ] && [ -f "$generated" ]; then
    "$jq" -r '._mode // "dark"' "$generated"
  else
    mode_of "$(current)"
  fi
}

saved_wallpaper_mode() {
  local mode=""
  [ -f "$wallpaper_mode_file" ] && mode=$(tr -d '[:space:]' <"$wallpaper_mode_file")
  case "$mode" in
    auto | smart | light | dark) printf '%s' "$mode" ;;
    *) printf 'auto' ;;
  esac
}

# Every file rendered from the palette assumes the same core keys. A truncated
# file, a failed write or a missing theme would otherwise reach the templates as
# `null`, which Yazi refuses to parse and the others render as a colour called
# "null". Checked before anything is written, so a bad palette leaves the
# previous files alone instead of replacing them with broken ones.
palette_ok() {
  "$jq" -e '
    type == "object" and
    ([.background, .surface, .surfaceContainer, .surfaceVariant,
      .foreground, .fgLight, .bgDark, .bgLight, .muted, .outline,
      .primary, .accent, .accentAlt, .secondary, .tertiary,
      .success, .yellow, .danger, .error]
      | all(type == "string" and test("^#[0-9a-fA-F]{6}$")))
  ' "$1" >/dev/null 2>&1
}

# A generated palette is the only one with `_mode`: curated palettes are written
# without it. That is what distinguishes a real wallpaper palette from the
# resolved palette a curated theme leaves in the same file.
wallpaper_palette() {
  [ -f "$generated" ] &&
    palette_ok "$generated" &&
    "$jq" -e 'has("_mode")' "$generated" >/dev/null 2>&1
}

# One colour out of the resolved palette. materialise() writes it for a curated
# theme; matugen writes it for a wallpaper.
colour() {
  local value
  value=$("$jq" -r --arg k "$1" '.[$k] // empty' "$generated")
  printf '%s' "$value"
}

ansi_colour() {
  local index="$1" fallback="$2" value
  value=$("$jq" -r --arg k "ansi$index" '.[$k] // empty' "$generated")
  if [ -z "$value" ]; then
    value=$("$jq" -r --arg k "$fallback" '.[$k] // empty' "$generated")
  fi
  printf '%s' "$value"
}

current() {
  local name=""
  [ -f "$current_file" ] && name=$(tr -d '[:space:]' <"$current_file")
  if [ -n "$name" ] && has "$name"; then
    printf '%s' "$name"
  else
    printf '%s' "$default_theme"
  fi
}

write_kitty_conf() {
  local file="$1"
  write_atomic "$file" <<EOF
background $(colour background)
foreground $(colour foreground)
selection_background $(colour accent)
selection_foreground $(colour background)
color0 $(ansi_colour 0 background)
color8 $(ansi_colour 8 muted)
color1 $(ansi_colour 1 danger)
color9 $(ansi_colour 9 danger)
color2 $(ansi_colour 2 success)
color10 $(ansi_colour 10 success)
color3 $(ansi_colour 3 yellow)
color11 $(ansi_colour 11 yellow)
color4 $(ansi_colour 4 primary)
color12 $(ansi_colour 12 primary)
color5 $(ansi_colour 5 accentAlt)
color13 $(ansi_colour 13 accentAlt)
color6 $(ansi_colour 6 accent)
color14 $(ansi_colour 14 accent)
color7 $(ansi_colour 7 foreground)
color15 $(ansi_colour 15 foreground)
EOF
}
