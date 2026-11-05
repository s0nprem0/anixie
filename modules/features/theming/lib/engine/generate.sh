#!/bin/bash
# Wallpaper generation logic
# shellcheck disable=SC2154
# Sourced by theme.sh, which defines the tools and state directories these
# functions use; checked standalone, shellcheck cannot see those assignments.

# Read the current wallpaper into a palette. Deliberately last in the order of
# things that can fail: a wallpaper matugen cannot parse leaves the previous
# palette in place rather than half-applying a new one. Results are cached by
# path, modification time and requested mode; videos use their first frame.
generate() {
  local wp="${1:-}" requested="${2:-auto}" json tmp
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
