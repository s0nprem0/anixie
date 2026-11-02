#!/bin/bash
# shellcheck disable=SC2034
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
#   theme state          the saved theme state as JSON
#   theme migrate        import the old separate state files
#   theme auto           apply the scheduled light or dark variant
#   theme favorite add|remove|toggle NAME
#   theme pin | unpin    keep auto from changing the current theme
#   theme export         print a Nix snippet for the current choice
#   theme info [NAME]    the mode, family and colours of one theme
#   theme doctor         check the live state and generated files
#   theme cursor-size N  set the cursor size and apply it now
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
tmux="@TMUX@"
auto_light=@AUTO_LIGHT@
auto_dark=@AUTO_DARK@
auto_schedule="@AUTO_SCHEDULE@"
cursor_theme="@CURSOR_THEME@"
cursor_size_default="@CURSOR_SIZE@"
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
palette_jq="@PALETTE_JQ@"
matugen_version=$("$matugen" --version 2>/dev/null | head -n 1)
palette_version=1

STATE_DIR="$state_dir"
DEFAULT_THEME="$default_theme"
JQ="$jq"
FLOCK="@FLOCK@"
AUTO_LIGHT="$auto_light"
AUTO_DARK="$auto_dark"
AUTO_SCHEDULE="$auto_schedule"

current_file="$state_dir/current"
wallpaper_mode_file="$state_dir/wallpaper-mode"
cursor_file="$state_dir/cursor-size"
live_link="$state_dir/live"
generations_dir="$state_dir/generations"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"
# shellcheck source=/dev/null
. "@COLOR_LIB@"
# shellcheck source=/dev/null
. "@STATE_LIB@"
# shellcheck source=/dev/null
. "@AUTO_LIB@"

# Load theming engine modules
engine_dir="$(dirname "$0")/lib/engine"
# shellcheck source=/dev/null
[ -f "$engine_dir/core.sh" ] && . "$engine_dir/core.sh"
# shellcheck source=/dev/null
[ -f "$engine_dir/generate.sh" ] && . "$engine_dir/generate.sh"
# shellcheck source=/dev/null
[ -f "$engine_dir/materialize.sh" ] && . "$engine_dir/materialize.sh"
# shellcheck source=/dev/null
[ -f "$engine_dir/apps.sh" ] && . "$engine_dir/apps.sh"

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
    gtk-3.0.css gtk-4.0.css share-picker.css tmux.conf btop.theme terminal.zsh; do
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

apply_cursor() {
  local size=""
  if [ -f "$cursor_file" ]; then
    size=$(tr -d '[:space:]' <"$cursor_file" 2>/dev/null || true)
  fi
  case "$size" in
    ''|*[!0-9]*) size="$cursor_size_default" ;;
  esac
  if [ "$size" -lt 8 ] || [ "$size" -gt 128 ]; then
    size="$cursor_size_default"
  fi
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface cursor-size "$size" >/dev/null 2>&1 || true
  "$hyprctl" setcursor "$cursor_theme" "$size" >/dev/null 2>&1 || true
}

tell_apps() {
  local name="$1" mode gtk_theme icon_theme color_scheme palette
  palette="$live_link/palette.json"

  if [ "$name" = "wallpaper" ]; then
    "$quickshell" ipc call theme palette "$(tr -d '\n' <"$palette" 2>/dev/null || tr -d '\n' <"$generated")" >/dev/null 2>&1 || true
  else
    "$quickshell" ipc call theme set "$name" >/dev/null 2>&1 || true
  fi
  "$hyprctl" reload >/dev/null 2>&1 || true
  pkill -USR1 -x kitty 2>/dev/null || true

  mode=$(tr -d '[:space:]' <"$live_link/mode" 2>/dev/null || tr -d '[:space:]' <"$state_dir/mode" 2>/dev/null || true)
  if [ "$mode" = "light" ]; then
    gtk_theme=adw-gtk3
    icon_theme=Papirus-Light
    color_scheme=prefer-light
  else
    gtk_theme=adw-gtk3-dark
    icon_theme=Papirus-Dark
    color_scheme=prefer-dark
  fi

  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface color-scheme "$color_scheme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface icon-theme "$icon_theme" >/dev/null 2>&1 || true
  accent=$(color_accent_name "$(colour primary)")
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface accent-color "$accent" >/dev/null 2>&1 || true

  apply_cursor
  "$tmux" source-file "$live_link/tmux.conf" >/dev/null 2>&1 || true
  "$wallpaper" apply >/dev/null 2>&1 || true
}

run_hooks() {
  local name="$1" mode hook_dir hook bg fg surface muted primary accent alt secondary tertiary yellow danger success error outline surface_container surface_variant bg_dark bg_light fg_light
  hook_dir="${XDG_CONFIG_HOME:-$HOME/.config}/anixie/theme-hooks"
  [ -d "$hook_dir" ] || return 0

  mode=$(tr -d '[:space:]' <"$live_link/mode" 2>/dev/null || printf 'dark')
  bg=$(colour background)
  fg=$(colour foreground)
  surface=$(colour surface)
  muted=$(colour muted)
  primary=$(colour primary)
  accent=$(colour accent)
  alt=$(colour accentAlt)
  secondary=$(colour secondary)
  tertiary=$(colour tertiary)
  yellow=$(colour yellow)
  danger=$(colour danger)
  success=$(colour success)
  error=$(colour error)
  outline=$(colour outline)
  surface_container=$(colour surfaceContainer)
  surface_variant=$(colour surfaceVariant)
  bg_dark=$(colour bgDark)
  bg_light=$(colour bgLight)
  fg_light=$(colour fgLight)

  for hook in "$hook_dir"/*.sh; do
    [ -x "$hook" ] || continue
    env ANIXIE_THEME="$name" ANIXIE_MODE="$mode" \
      ANIXIE_BG="$bg" ANIXIE_FG="$fg" ANIXIE_SURFACE="$surface" \
      ANIXIE_MUTED="$muted" ANIXIE_PRIMARY="$primary" ANIXIE_ACCENT="$accent" \
      ANIXIE_ACCENT_ALT="$alt" ANIXIE_SECONDARY="$secondary" ANIXIE_TERTIARY="$tertiary" \
      ANIXIE_YELLOW="$yellow" ANIXIE_DANGER="$danger" ANIXIE_ERROR="$error" \
      ANIXIE_SUCCESS="$success" ANIXIE_OUTLINE="$outline" \
      ANIXIE_SURFACE_CONTAINER="$surface_container" ANIXIE_SURFACE_VARIANT="$surface_variant" \
      ANIXIE_BG_DARK="$bg_dark" ANIXIE_BG_LIGHT="$bg_light" ANIXIE_FG_LIGHT="$fg_light" \
      "$hook" >/dev/null 2>&1 || true
  done
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
  key=$(printf '%s\n%s\n%s\n%s\n%s\n' "$wp" "$mtime" "$requested" "$palette_version" "$matugen_version" | "$sha256sum")
  key=${key%% *}
  cache_dir="$state_dir/cache"
  cache="$cache_dir/palette-$key.json"
  mkdir -p "$cache_dir" || die "could not create $cache_dir"
  find "$cache_dir" -type f -mtime +30 -delete 2>/dev/null || true

  if [ -f "$cache" ]; then
    if palette_ok "$cache" && "$jq" -e '._mode == "dark" or ._mode == "light"' "$cache" >/dev/null 2>&1; then
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
  [ -n "$json" ] || die "matugen wrote no palette"

  tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
  printf '%s' "$json" | "$jq" -f "$palette_jq" --arg fallback "$requested" >"$tmp" \
    || die "could not read the generated palette"
  palette_ok "$tmp" || die "matugen returned an incomplete palette"
  color_palette_fix "$tmp" || die "could not adjust the generated palette"
  palette_ok "$tmp" || die "the adjusted palette is incomplete"
  mv "$tmp" "$generated"

  tmp=$(mktemp "$cache.XXXXXX") || die "could not create a cache file"
  cp "$generated" "$tmp" && mv "$tmp" "$cache" || die "could not cache the palette"
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
  state_lock || die "could not lock the theme state"
  generate "$wp" "$requested"
  materialise wallpaper
  state_unlock
  # A named picture is the background the palette came from. `wallpaper use`
  # has already recorded its own choice (and may have recorded it for one
  # output only), so it sets ANIXIE_WALLPAPER_RECORDED to keep this from
  # replacing that with a global one.
  if [ -n "$wp" ] && [ "${ANIXIE_WALLPAPER_RECORDED:-}" != "1" ]; then
    "$wallpaper" record "$wp" >/dev/null \
      || printf 'theme: could not record the wallpaper choice\n' >&2
  fi
  tell_apps wallpaper
  run_hooks wallpaper
  printf 'Theme: wallpaper\n'
}

set_cursor_size() {
  value="$1"
  case "$value" in
    "" | *[!0-9]*) die "cursor-size needs a number" ;;
  esac
  [ "$value" -ge 8 ] && [ "$value" -le 128 ] \
    || die "cursor-size must be between 8 and 128"
  mkdir -p "$state_dir" || die "could not create $state_dir"
  printf '%s\n' "$value" >"$cursor_file" || die "could not write $cursor_file"
  apply_cursor
}

auto_theme() {
  state_ensure || die "could not read the theme state"
  [ "$AUTO_SCHEDULE" = "true" ] || return 0
  [ "$("$jq" -r '.pinned // false' "$state_dir/state.json")" = "true" ] && return 0

  light="$auto_light"
  dark="$auto_dark"

  target=$(auto_mode "$light" "$dark")

  [ "$(current_mode)" = "$target" ] && return 0
  name=$(current)

  if [ "$name" = "wallpaper" ]; then
    source=$("$jq" -r --arg t wallpaper '.themes[$t].fallback.path // empty' "$state_dir/wallpapers.json" 2>/dev/null || true)
    if [ -n "$source" ] && [ -f "$source" ]; then
      wallpaper_theme "$source" "$target"
    fi
    return 0
  fi

  pair=$("$jq" -r --arg n "$name" '.[$n]._pair // empty' "$palettes")
  if [ -z "$pair" ] || [ "$pair" = "null" ]; then
    family=$("$jq" -r --arg n "$name" '.[$n]._family // empty' "$palettes")
    pair=$("$jq" -r --arg family "$family" --arg mode "$target" --arg current "$name" '
      to_entries[]
      | select(.value._mode == $mode and (.value._family // "") == $family and .key != $current)
      | .key
    ' "$palettes" | head -n 1)
  fi

  if [ -z "$pair" ] || [ "$pair" = "null" ]; then
    pair=$("$jq" -r --arg mode "$target" --arg current "$name" '
      to_entries[]
      | select(.value._mode == $mode and .key != $current)
      | .key
    ' "$palettes" | head -n 1)
    if [ -n "$pair" ] && [ "$pair" != "null" ]; then
      printf 'theme: auto falling back to %s (no pair/family match)\n' "$pair" >&2
    fi
  fi

  if [ -n "$pair" ] && [ "$pair" != "null" ] && has "$pair"; then
    set_theme "$pair"
  elif [ "${ANIXIE_THEME_DEBUG:-}" = "1" ]; then
    printf 'theme: auto could not find %s theme for %s\n' "$target" "$name" >&2
  fi
}


favorite_theme() {
  action="$1"
  name="$2"
  has "$name" || die "no theme called \"$name\" (try: theme list)"
  state_ensure || die "could not read the theme state"

  case "$action" in
    add) filter='.favorites = ((.favorites // []) + [$name] | unique)' ;;
    remove) filter='.favorites = ((.favorites // []) | map(select(. != $name)))' ;;
    toggle)
      filter='if ((.favorites // []) | index($name)) then .favorites = ((.favorites // []) | map(select(. != $name))) else .favorites = (((.favorites // []) + [$name]) | unique) end'
      ;;
    *) die "favorite must be add, remove or toggle" ;;
  esac

  tmp=$(mktemp "$state_dir/.state.XXXXXX") || die "could not create the theme state"
  if "$jq" --arg name "$name" ".version = 1 | $filter" "$state_dir/state.json" >"$tmp"; then
    mv "$tmp" "$state_dir/state.json"
  else
    rm -f "$tmp"
    die "could not update favorites"
  fi
}

pin_theme() {
  value="$1"
  state_ensure || die "could not read the theme state"
  tmp=$(mktemp "$state_dir/.state.XXXXXX") || die "could not create the theme state"
  if "$jq" --argjson value "$value" '.version = 1 | .pinned = $value' "$state_dir/state.json" >"$tmp"; then
    mv "$tmp" "$state_dir/state.json"
  else
    rm -f "$tmp"
    die "could not update the pin"
  fi
}

export_theme() {
  name=$(current)
  if [ "$name" = "wallpaper" ]; then
    printf '# the live theme is generated from a wallpaper\n'
    printf '# choose a preset, then run: anixie theme export\n'
    return
  fi
  escaped=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf 'anixie.theme.theme = "%s";\n' "$escaped"
}

doctor_theme() {
  state_ensure || die "could not read the theme state"
  live=$(readlink "$live_link" 2>/dev/null || true)
  failures=0
  warnings=0

  if [ -z "$live" ] || [ ! -f "$live_link/palette.json" ]; then
    printf 'missing  live generation\n'
    failures=$((failures + 1))
  else
    printf 'ok       live generation %s\n' "$(basename "$live")"
    if ! palette_ok "$live_link/palette.json"; then
      printf 'invalid  live palette\n'
      failures=$((failures + 1))
    else
      printf 'ok       palette\n'
    fi
    for file in kitty.conf helix.toml yazi.toml hyprlock.conf qt6ct.conf qt5ct.conf kvantum.kvconfig \
      gtk-3.0-settings.ini gtk-4.0-settings.ini gtk-3.0.css gtk-4.0.css share-picker.css tmux.conf btop.theme terminal.zsh; do
      if [ ! -s "$live_link/$file" ]; then
        printf 'missing  %s\n' "$file"
        failures=$((failures + 1))
      fi
    done
    if grep -R -q '@[A-Z][A-Z0-9_]*@' "$live_link" 2>/dev/null; then
      printf 'invalid  unresolved placeholders in the live generation\n'
      failures=$((failures + 1))
    fi

    # Contrast checks for critical text tokens
    if [ -f "$live_link/palette.json" ]; then
      for pair in "muted:surface muted:background fgLight:surface fgLight:background"; do
        fg_tok=${pair%%:*}
        bg_tok=${pair#*:}
        fg_c=$("$jq" -r --arg k "$fg_tok" '.[$k] // empty' "$live_link/palette.json")
        bg_c=$("$jq" -r --arg k "$bg_tok" '.[$k] // empty' "$live_link/palette.json")
        if [ -n "$fg_c" ] && [ -n "$bg_c" ]; then
          ratio=$(color_contrast "$fg_c" "$bg_c" 2>/dev/null || printf '0')
          if awk -v r="$ratio" 'BEGIN { exit !(r < 4.5) }'; then
            printf 'warn     %s vs %s contrast %.2f < 4.5\n' "$fg_tok" "$bg_tok" "$ratio"
            warnings=$((warnings + 1))
          fi
        fi
      done
    fi
  fi

  # Check symlink integrity for config files
  for cfg in helix/themes/anixie.toml yazi/theme.toml hypr/hyprlock.conf btop/themes/anixie.theme; do
    full="${XDG_CONFIG_HOME:-$HOME/.config}/$cfg"
    if [ -e "$full" ] && [ ! -L "$full" ]; then
      printf 'warn     %s is not a symlink\n' "$full"
      warnings=$((warnings + 1))
    fi
  done

  # Check runtime dependencies
  if ! command -v "$quickshell" >/dev/null 2>&1; then
    printf 'warn     quickshell not found in PATH\n'
    warnings=$((warnings + 1))
  fi
  if ! command -v "$hyprctl" >/dev/null 2>&1; then
    printf 'warn     hyprctl not found in PATH\n'
    warnings=$((warnings + 1))
  fi

  if [ -f "$state_dir/wallpapers.json" ]; then
    if "$jq" -e . "$state_dir/wallpapers.json" >/dev/null 2>&1; then
      printf 'ok       wallpaper state\n'
    else
      printf 'invalid  wallpaper state\n'
      failures=$((failures + 1))
    fi
  fi

  if [ "$failures" -ne 0 ]; then
    printf '%s problem(s), %s warning(s)\n' "$failures" "$warnings"
    return 1
  fi
  if [ "$warnings" -ne 0 ]; then
    printf 'no problems found, %s warning(s)\n' "$warnings"
    return 0
  fi
  printf 'no problems found\n'
}

step() {
  local direction="$1" here target
  here=$(current)

  # Sorted order, wrapping at both ends, so next from the last is the first.
  target=$(
    names | awk -v here="$here" -v dir="$direction" '
      { list[NR] = $0; if ($0 == here) at = NR }
      END {
        if (NR == 0) exit 1
        # A generated wallpaper is not in the list. Stepping away from it starts
        # at the first theme going forward and the last going back.
        if (at == 0) at = (dir == "next") ? 0 : 1
        if (dir == "next") at = (at % NR) + 1
        else at = ((at - 2 + NR) % NR) + 1
        if (at < 1 || at > NR) at = 1
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
    [ $# -le 1 ] || die "list takes no arguments"
    names | while IFS= read -r name; do
      [ -z "$name" ] && continue
      mode="$(mode_of "$name")"
      printf '\033[1m%s\033[0m \033[2m(%s)\033[0m\n' "$name" "$mode"
    done
    ;;
  current)
    [ $# -le 1 ] || die "current takes no arguments"
    current
    ;;
  state)
    [ $# -le 1 ] || die "state takes no arguments"
    state_ensure || die "could not initialise $state_dir/state.json"
    state_json
    ;;
  migrate)
    [ $# -le 1 ] || die "migrate takes no arguments"
    state_migrate || die "could not migrate the theme state"
    state_json
    ;;
  auto)
    [ $# -le 1 ] || die "auto takes no arguments"
    auto_theme
    ;;
  favorite)
    [ $# -eq 3 ] || die "favorite needs add|remove|toggle and a theme name"
    favorite_theme "$2" "$3"
    ;;
  pin)
    [ $# -le 1 ] || die "pin takes no arguments"
    pin_theme true
    ;;
  unpin)
    [ $# -le 1 ] || die "unpin takes no arguments"
    pin_theme false
    ;;
  export)
    [ $# -le 1 ] || die "export takes no arguments"
    export_theme
    ;;
  info)
    [ $# -le 2 ] || die "info takes an optional theme name"
    theme_name="${2:-$(current)}"
    if [ "$theme_name" = "wallpaper" ]; then
      printf 'Theme: wallpaper (generated)\n'
      if [ -f "$generated" ]; then
        mode=$("$jq" -r '._mode // "dark"' "$generated" 2>/dev/null || printf 'dark')
        printf 'Mode:   %s\n' "$mode"
        printf 'Source: matugen from wallpaper\n'
      fi
      exit 0
    fi
    has "$theme_name" || die "no theme called \"$theme_name\" (try: theme list)"
    mode=$("$jq" -r --arg n "$theme_name" '.[$n]._mode // "dark"' "$palettes")
    family=$("$jq" -r --arg n "$theme_name" '.[$n]._family // ""' "$palettes")
    pair=$("$jq" -r --arg n "$theme_name" '.[$n]._pair // ""' "$palettes")
    variant=$("$jq" -r --arg n "$theme_name" '.[$n]._variant // ""' "$palettes")
    printf 'Theme:   %s\n' "$theme_name"
    printf 'Mode:    %s\n' "$mode"
    [ -n "$family" ] && [ "$family" != "null" ] && printf 'Family:  %s\n' "$family"
    [ -n "$variant" ] && [ "$variant" != "null" ] && printf 'Variant: %s\n' "$variant"
    [ -n "$pair" ] && [ "$pair" != "null" ] && printf 'Pair:    %s\n' "$pair"
    printf '\n'
    for key in background surface primary accent foreground muted success yellow danger; do
      val=$("$jq" -r --arg n "$theme_name" --arg k "$key" '.[$n][$k]' "$palettes")
      printf '  %s\t%s\n' "$key" "$val"
    done
    ;;
  doctor)
    [ $# -le 1 ] || die "doctor takes no arguments"
    doctor_theme
    ;;
  cursor-size)
    [ $# -eq 2 ] || die "cursor-size needs exactly one number"
    case "$2" in
      *[!0-9]*) die "cursor-size must be a positive integer" ;;
    esac
    set_cursor_size "$2"
    ;;
  apply)
    [ $# -le 1 ] || die "apply takes no arguments"
    # Login runs this after every boot. When the live generation already
    # matches the saved theme and was made by the current renderer, re-rendering
    # it is pure work: the files are on disk. Tell the apps about it instead,
    # and only materialise on a fresh state or after a rebuild changed the
    # palettes or the renderer.
    state_lock || die "could not lock the theme state"
    name=$(current)
    state_theme=$("$jq" -r '.theme // ""' "$state_dir/state.json" 2>/dev/null || true)
    renderer=$(cat "$live_link/renderer" 2>/dev/null || true)
    if [ ! -f "$live_link/palette.json" ] ||
      [ "$state_theme" != "$name" ] ||
      [ "$renderer" != "$palettes @THEME_APPS@" ]; then
      materialise "$name"
    fi
    state_unlock
    tell_apps "$name"
    run_hooks "$name"
    ;;
  set)
    [ $# -eq 2 ] || die "set needs exactly one theme name"
    set_theme "$2"
    ;;
  wallpaper)
    [ $# -ge 2 ] && [ $# -le 3 ] || die "wallpaper needs a file and optional mode"
    wallpaper_theme "${2:-}" "${3:-}"
    ;;
  wallpaper-mode)
    if [ $# -ge 2 ]; then
      [ $# -eq 2 ] || die "wallpaper-mode takes at most one mode"
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
    [ $# -le 1 ] || die "next takes no arguments"
    step next
    ;;
  prev | previous)
    [ $# -le 1 ] || die "prev takes no arguments"
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
