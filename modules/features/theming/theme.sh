#!/bin/bash
# Themes.
#
#   theme                pick one
#   theme list           the names, one per line
#   theme current        the name in use
#   theme set NAME       switch to it
#   theme wallpaper [FILE] [auto|light|dark]
#                        derive a palette from a picture
#   theme wallpaper-mode [auto|light|dark]
#                        remember the mode for the next picture
#   theme next | prev    step through the list
#   theme apply          re-apply the current one (run at login)
#
# One palette drives the shell, the compositor's window borders, the terminal and
# the launcher. The shell is told over its IPC and switches immediately; Hyprland
# reloads, kitty takes SIGUSR1, and the rest read the files written here.
#
# btop, tmux, Helix, Yazi and hyprlock are rewritten on every switch, along with
# the resolved palette that Hyprland and the wallpaper command read. GTK gets a
# fresh settings.ini plus the gsettings colour scheme; Qt gets a qt6ct palette.
# Applications that read their config at startup pick the new palette up then;
# nothing here needs a rebuild.
#
# The palettes are a JSON file rather than a Nix expression because this script
# has to read the same list the shell was built from, and a shell script cannot
# evaluate Nix. One file, two readers, nothing to keep in step by hand.

set -uo pipefail

palettes="@PALETTES@"
state_dir="@STATE_DIR@"
default_theme="@DEFAULT_THEME@"

quickshell="@QUICKSHELL@"
matugen="@MATUGEN@"
generated="@GENERATED@"
hyprctl="@HYPRCTL@"
gsettings="@GSETTINGS@"
gsettings_schema_dir="@GSETTINGS_SCHEMA_DIR@"
jq="@JQ@"
wallpaper="@WALLPAPER@"
magick="@MAGICK@"
ffmpeg="@FFMPEG@"
sha256sum="@SHA256SUM@"
stat="@STAT@"

current_file="$state_dir/current"
wallpaper_mode_file="$state_dir/wallpaper-mode"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# Write a file through a temporary in the same directory, so a failure never
# leaves a half-written palette or config behind.
write_atomic() {
  local file="$1" tmp
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if cat >"$tmp"; then
    mv "$tmp" "$file"
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
# previous files alone instead of replacing them with broken ones. `yellow` is
# optional because a palette generated before that token existed falls back to
# the accent.
palette_ok() {
  "$jq" -e '
    type == "object" and
    ([.background, .foreground, .surface, .muted, .primary, .accent,
      .accentAlt, .danger, .success]
      | all(type == "string" and length > 0))
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
  # A palette generated before the ANSI yellow token existed still has a usable
  # accent; use it rather than writing "null" into kitty's colour3.
  if [ -z "$value" ] && [ "$1" = "yellow" ]; then
    value=$("$jq" -r '.["accent"]' "$generated")
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

# Write the files the apps read. Everything that follows a theme is materialised
# here rather than rendered at build time, because a build-time value cannot
# change without a rebuild.
materialise() {
  local name="$1" tmp
  mkdir -p "$state_dir" || die "could not create $state_dir"

  if [ "$name" = "wallpaper" ]; then
    wallpaper_palette || die "the generated palette is missing; run 'theme wallpaper FILE'"
  else
    "$jq" -e --arg n "$name" '.[$n] | type == "object"' "$palettes" >/dev/null 2>&1 \
      || die "no such theme: $name"
    tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
    "$jq" --arg n "$name" '.[$n] | del(._mode)' "$palettes" >"$tmp" \
      || die "could not resolve $name"
    palette_ok "$tmp" || die "theme $name is missing colours"
    mv "$tmp" "$generated"
  fi

  # The mode is metadata, not a colour: the build-time configs need it, and so
  # does a runtime switch of the glass theme.
  if [ "$name" = "wallpaper" ]; then
    "$jq" -r '._mode // "dark"' "$generated" | write_atomic "$state_dir/mode" \
      || die "could not write $state_dir/mode"
  else
    "$jq" -r --arg n "$name" '.[$n]._mode // "dark"' "$palettes" | write_atomic "$state_dir/mode" \
      || die "could not write $state_dir/mode"
  fi

  printf '%s\n' "$name" | write_atomic "$current_file" \
    || die "could not write $current_file"

  # kitty reads this through an include in its generated config, so the same four
  # settings appear whether the theme was built in or set at runtime.
  write_atomic "$state_dir/kitty.conf" <<EOF || die "could not write $state_dir/kitty.conf"
background $(colour background)
foreground $(colour foreground)
selection_background $(colour accent)
selection_foreground $(colour background)
color0 $(colour background)
color8 $(colour muted)
color1 $(colour danger)
color9 $(colour danger)
color2 $(colour success)
color10 $(colour success)
color3 $(colour yellow)
color11 $(colour yellow)
color4 $(colour primary)
color12 $(colour primary)
color5 $(colour accentAlt)
color13 $(colour accentAlt)
color6 $(colour accent)
color14 $(colour accent)
color7 $(colour foreground)
color15 $(colour foreground)
EOF

  # tmux, btop, and whichever others have learned to read the state directory.
  # A failure here must not take the theme switch with it — the shell and the
  # terminal have already changed by this point.
  "@THEME_APPS@" "$name" >/dev/null 2>&1 || true
}

# The compositor and the terminal have to be told. The shell is told through its
# IPC rather than left to notice: it reads the state file once at startup, and a
# FileView watch on it never fired on this Quickshell, so a running shell has no
# other way to hear about the change.
tell_apps() {
  local name="$1" mode gtk_theme icon_theme color_scheme

  # A generated palette cannot be named to the shell — the shell was built with
  # the curated ones — so it is handed over whole.
  if [ "$name" = "wallpaper" ]; then
    "$quickshell" ipc call theme palette "$(tr -d '\n' <"$generated")" >/dev/null 2>&1 || true
  else
    "$quickshell" ipc call theme set "$name" >/dev/null 2>&1 || true
  fi
  "$hyprctl" reload >/dev/null 2>&1 || true
  pkill -USR1 -x kitty 2>/dev/null || true

  # GTK reads the mode rather than only the palette: the dark and light variants
  # are separate themes, and the icon set has a matching pair.
  mode=$(tr -d '[:space:]' <"$state_dir/mode" 2>/dev/null || true)
  if [ "$mode" = "light" ]; then
    gtk_theme=Adwaita
    icon_theme=Papirus-Light
    color_scheme=prefer-light
  else
    gtk_theme=Adwaita-dark
    icon_theme=Papirus-Dark
    color_scheme=prefer-dark
  fi

  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface color-scheme "$color_scheme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface icon-theme "$icon_theme" >/dev/null 2>&1 || true

  # Qt reads qt6ct's config when an application starts. The file lives in the
  # state directory and is linked into ~/.config by the Nix module.
  write_atomic "$state_dir/qt6ct.conf" <<EOF || die "could not write $state_dir/qt6ct.conf"
[Appearance]
color_scheme_path=$state_dir/qt6ct-colors.conf
custom_palette=true
icon_theme=$icon_theme
style=Fusion
EOF

  # The wallpaper follows the palette unless one of your own is set, in which
  # case this is a no-op — the `wallpaper` command owns that decision.
  "$wallpaper" apply >/dev/null 2>&1 || true
}

# Read the current wallpaper into a palette. Deliberately last in the order of
# things that can fail: a wallpaper matugen cannot parse leaves the previous
# palette in place rather than half-applying a new one. Results are cached by
# path, modification time and requested mode; videos use their first frame.
generate() {
  local wp="${1:-}" requested="${2:-auto}" mode json tmp
  local source mtime key cache_dir cache frame saturation mono
  local -a args
  mkdir -p "$state_dir" || die "could not create $state_dir"

  case "$requested" in
    "" | auto | smart) requested=smart ;;
    light | dark) ;;
    *) die "mode must be auto, light or dark" ;;
  esac

  # A picture can be named, and otherwise the current one is used — but only if it
  # is a file. The generated wallpaper is a gradient made *from* the palette, so
  # reading a palette out of it is a circle; saying so is better than reporting
  # that there is no wallpaper at all.
  [ -n "$wp" ] || wp=$("$wallpaper" current 2>/dev/null || true)

  [ -n "$wp" ] && [ -f "$wp" ] || die "no picture to read a palette from — set one with 'wallpaper set FILE', or name one: 'theme wallpaper FILE'"

  # The default background is a gradient made from the palette. Reading it back
  # would be a circle, and it would happily overwrite the palette that made it.
  if [ "$(readlink -f "$wp")" = "$(readlink -f "$state_dir/wallpaper.png")" ]; then
    die "the current background is generated from the palette; set a picture with 'wallpaper set FILE' first"
  fi

  # Cache the result per path, modification time and mode. Re-selecting the same
  # wallpaper is then instant, and an overwritten file is read again.
  mtime=$("$stat" -Lc %Y "$wp" 2>/dev/null || printf '0')
  key=$(printf '%s\n%s\n%s\n' "$wp" "$mtime" "$requested" | "$sha256sum")
  key=${key%% *}
  cache_dir="$state_dir/cache"
  cache="$cache_dir/palette-$key.json"
  mkdir -p "$cache_dir" || die "could not create $cache_dir"
  find "$cache_dir" -type f -mtime +30 -delete 2>/dev/null || true

  if [ -f "$cache" ]; then
    if "$jq" -e 'has("background") and has("surface") and has("foreground") and has("muted") and has("primary") and has("accent") and has("accentAlt") and has("success") and has("danger") and (._mode == "dark" or ._mode == "light")' "$cache" >/dev/null 2>&1; then
      tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
      cp "$cache" "$tmp" && mv "$tmp" "$generated" || die "could not use the cached palette"
      return
    fi
    rm -f "$cache"
  fi

  source="$wp"
  case "$(printf '%s' "${source##*.}" | tr '[:upper:]' '[:lower:]')" in
    mp4 | m4v | mov | webm | mkv | avi | ogv)
      frame="$cache_dir/frame-$key.jpg"
      if [ ! -f "$frame" ]; then
        "$ffmpeg" -y -loglevel error -i "$source" -frames:v 1 -q:v 2 "$frame" \
          || die "could not read a frame from $wp"
      fi
      source="$frame"
      ;;
  esac

  # A monochrome picture would otherwise get a tinted Material palette; ask
  # matugen for the neutral one instead.
  saturation=$("$magick" "$source" -colorspace HSL -channel G -separate \
    -format '%[fx:mean]' info: 2>/dev/null || printf '1')
  if awk -v s="$saturation" 'BEGIN { exit !(s < 0.08) }'; then
    mono=1
  else
    mono=0
  fi

  args=(image "$source" --mode "$requested" --source-color-index 0 --json hex)
  # --source-color-index keeps matugen from asking which colour to use: that
  # prompt is a hard error when this runs from a keybind or a service.
  if [ "$mono" = "1" ]; then
    args+=(--type scheme-monochrome)
  fi

  json=$("$matugen" "${args[@]}" 2>/dev/null) \
    || die "matugen could not read $source"
  [ -f "$generated" ] || die "matugen wrote no palette"

  mode=$(printf '%s' "$json" | "$jq" -r '.mode // empty' 2>/dev/null || true)
  if [ -z "$mode" ]; then
    if [ "$requested" = "smart" ]; then mode=dark; else mode=$requested; fi
  fi

  # Keep the mode with the palette so the shell can style light surfaces and a
  # later `theme apply` knows what it is applying without asking matugen again.
  tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
  "$jq" --arg mode "$mode" '. + {_mode: $mode}' "$generated" >"$tmp" \
    || die "could not read the generated palette"
  mv "$tmp" "$generated"

  tmp=$(mktemp "$cache.XXXXXX") || die "could not create a cache file"
  cp "$generated" "$tmp" && mv "$tmp" "$cache" || die "could not cache the palette"
}

set_theme() {
  local name="$1"
  has "$name" || die "no theme called \"$name\" (try: theme list)"
  materialise "$name"
  tell_apps "$name"
  printf 'Theme: %s\n' "$name"
}

wallpaper_theme() {
  local wp="${1:-}" requested="${2:-}"
  if [ -n "$requested" ]; then
    case "$requested" in
      auto | smart | light | dark) ;;
      *) die "mode must be auto, light or dark" ;;
    esac
    printf '%s\n' "$requested" | write_atomic "$wallpaper_mode_file" \
      || die "could not write $wallpaper_mode_file"
  else
    requested=$(saved_wallpaper_mode)
  fi
  generate "$wp" "$requested"
  set_theme wallpaper
}

step() {
  local direction="$1" here target
  here=$(current)

  # Sorted order, wrapping at both ends, so next from the last is the first.
  target=$(
    names | awk -v here="$here" -v dir="$direction" '
      { list[NR] = $0; if ($0 == here) at = NR }
      END {
        # A generated wallpaper is not in the list. Stepping away from it starts
        # at the first theme going forward and the last going back.
        if (at == 0) at = (dir == "next") ? 0 : 1
        if (dir == "next") at = (at % NR) + 1
        else at = ((at - 2 + NR) % NR) + 1
        print list[at]
      }'
  )

  [ -n "$target" ] || die "could not work out the next theme"
  set_theme "$target"
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  list)
    names
    ;;
  current)
    current
    ;;
  apply)
    # No change, just make sure the files match the saved choice — this is what
    # login runs, since a fresh boot has the state directory but not the files.
    materialise "$(current)"
    tell_apps "$(current)"
    ;;
  set)
    [ $# -ge 2 ] || die "set needs a theme name"
    set_theme "$2"
    ;;
  wallpaper)
    wallpaper_theme "${2:-}" "${3:-}"
    ;;
  wallpaper-mode)
    if [ $# -ge 2 ]; then
      case "$2" in
        auto | light | dark)
          printf '%s\n' "$2" | write_atomic "$wallpaper_mode_file" \
            || die "could not write $wallpaper_mode_file"
          ;;
        *) die "wallpaper-mode must be auto, light or dark" ;;
      esac
    else
      saved_wallpaper_mode
      printf '\n'
    fi
    ;;
  next)
    step next
    ;;
  prev | previous)
    step prev
    ;;
  "")
    # The picker runs `theme set <name>` itself, so this has nothing left to do
    # but hand over the names and be done. The label carries the mode; the value
    # stays the name, so the command it runs does not change.
    {
      if wallpaper_palette; then
        if [ -f "$state_dir/wallpaper.png" ]; then
          printf 'wallpaper (generated)\twallpaper\t\t\t%s\n' "$state_dir/wallpaper.png"
        else
          printf 'wallpaper (generated)\twallpaper\n'
        fi
      fi
      names | while IFS= read -r name; do
        preview=$(theme_preview "$name" 2>/dev/null || true)
        printf '%s (%s)\t%s\t\t\t%s\n' "$name" "$(mode_of "$name")" "$name" "$preview"
      done
    } | pick --title 'theme' --on-select 'theme set {}'
    exit 0
    ;;
  *)
    printf 'theme: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
