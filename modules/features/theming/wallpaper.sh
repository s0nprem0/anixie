#!/bin/sh
# Desktop wallpaper.
#
# The default is not a picture but a gradient generated from the live palette, so
# every theme brings its own without shipping image files, and switching theme
# repaints the wallpaper with it. Point it at a file instead and that is used
# until told to go back.
#
#   wallpaper            apply the current wallpaper (generate if needed)
#   wallpaper theme      go back to the generated one
#   wallpaper set FILE   use a picture of your own
#   wallpaper current    print which is in use
#
# awww holds the image up, the way swww does; the daemon is started by Hyprland.
set -eu

STATE="@STATE_DIR@"
PALETTES="@PALETTES@"
DEFAULT_THEME="@DEFAULT_THEME@"
JQ="@JQ@"
MAGICK="@MAGICK@"
AWWW="@AWWW@"
AWWW_DAEMON="@AWWW_DAEMON@"
WIDTH="@WIDTH@"
HEIGHT="@HEIGHT@"

CUSTOM="$STATE/wallpaper.custom"
GENERATED="$STATE/wallpaper.png"

current_theme() {
  if [ -f "$STATE/current" ]; then
    tr -d '[:space:]' <"$STATE/current"
  else
    echo "$DEFAULT_THEME"
  fi
}

colour() {
  # shellcheck disable=SC2016  # the jq program is single-quoted on purpose
  "$JQ" -r --arg n "$1" --arg k "$2" '.[$n][$k]' "$PALETTES"
}

# A soft diagonal wash from the background to the surface, with the primary
# colour as a faint vignette so the palette's accent is present without a picture
# in the way of the windows.
generate() {
  mkdir -p "$STATE"
  theme="$(current_theme)"
  bg="$(colour "$theme" background)"
  surface="$(colour "$theme" surface)"
  primary="$(colour "$theme" primary)"

  "$MAGICK" -size "${WIDTH}x${HEIGHT}" \
    gradient:"$bg"-"$surface" \
    \( -size "${WIDTH}x${HEIGHT}" radial-gradient:none-"$primary" \
    -alpha set -channel A -evaluate multiply 0.10 +channel \) \
    -compose over -composite \
    "$GENERATED"
}

apply() {
  if [ -f "$CUSTOM" ] && [ -f "$(cat "$CUSTOM")" ]; then
    img="$(cat "$CUSTOM")"
  else
    generate
    img="$GENERATED"
  fi

  # The daemon is started by Hyprland, but the login-time apply can beat it. Start
  # it here when it is missing rather than leave the first login without a
  # wallpaper until the next theme change.
  if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    "$AWWW_DAEMON" >/dev/null 2>&1 &
    sleep 1
  fi

  "$AWWW" img "$img" --transition-type grow --transition-duration 1 2>/dev/null ||
    "$AWWW" img "$img" 2>/dev/null || true
}

case "${1:-}" in
  "" | apply | theme) apply ;;
  set)
    [ $# -ge 2 ] || { echo "wallpaper: set needs a file" >&2; exit 1; }
    [ -f "$2" ] || { echo "wallpaper: no such file: $2" >&2; exit 1; }
    mkdir -p "$STATE"
    printf '%s\n' "$2" >"$CUSTOM"
    apply
    ;;
  current)
    if [ -f "$CUSTOM" ] && [ -f "$(cat "$CUSTOM")" ]; then
      cat "$CUSTOM"
    else
      echo "generated from theme $(current_theme)"
    fi
    ;;
  *) printf 'wallpaper: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
esac
