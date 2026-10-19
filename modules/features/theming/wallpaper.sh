#!/bin/sh
# Desktop wallpaper.
#
# The default is not a picture but a gradient generated from the live palette, so
# every theme brings its own without shipping image files, and switching theme
# repaints the wallpaper with it. On top of that each theme has a folder of your
# own backgrounds, and this is the picker over them:
#
#   wallpaper            pick one (the generated default, or a file)
#   wallpaper list       what the current theme offers
#   wallpaper set FILE   add a picture and use it
#   wallpaper add DIR    add every picture in a folder
#   wallpaper next|prev  step through the collection
#   wallpaper generated  go back to the palette gradient
#   wallpaper apply      re-apply the saved choice (run at login)
#   wallpaper current    which background is in use
#
# The choice is remembered per theme, so switching away and back restores it.
# Backgrounds live beside the other user data, not in ~/.config, which Home
# Manager owns read-only — the same reason the theme state does.
set -eu

STATE="@STATE_DIR@"
BACKGROUNDS="@DATA_DIR@/backgrounds"
PALETTES="@PALETTES@"
DEFAULT_THEME="@DEFAULT_THEME@"
JQ="@JQ@"
MAGICK="@MAGICK@"
AWWW="@AWWW@"
AWWW_DAEMON="@AWWW_DAEMON@"
WIDTH="@WIDTH@"
HEIGHT="@HEIGHT@"

GENERATED="$STATE/wallpaper.png"

current_theme() {
  if [ -f "$STATE/current" ]; then
    tr -d '[:space:]' <"$STATE/current"
  else
    echo "$DEFAULT_THEME"
  fi
}

theme_dir() {
  echo "$BACKGROUNDS/$(current_theme)"
}

# The saved choice for a theme: a path, or the word "generated".
choice_file() {
  echo "$STATE/wallpaper.$(current_theme)"
}

chosen() {
  f="$(choice_file)"
  if [ -f "$f" ]; then
    cat "$f"
  else
    echo generated
  fi
}

# shellcheck disable=SC2016  # the jq program is single-quoted on purpose
colour() {
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
  choice="$(chosen)"
  if [ "$choice" = generated ] || [ ! -f "$choice" ]; then
    generate
    img="$GENERATED"
  else
    img="$choice"
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

remember() {
  mkdir -p "$STATE"
  printf '%s\n' "$1" >"$(choice_file)"
}

# The list the picker and `next` walk: the generated default first, then every
# file in the theme's folder, alphabetically.
entries() {
  dir="$(theme_dir)"
  echo generated
  if [ -d "$dir" ]; then
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      echo "$f"
    done
  fi
}

pick_one() {
  dir="$(theme_dir)"
  mkdir -p "$dir"
  {
    printf 'Generated (from the %s palette)\tgenerated\n' "$(current_theme)"
    if [ -d "$dir" ]; then
      for f in "$dir"/*; do
        [ -f "$f" ] || continue
        printf '%s\t%s\n' "$(basename "$f")" "$f"
      done
    fi
  } | pick --title "wallpaper — $(current_theme)" --on-select 'wallpaper use {}'
}

step() {
  direction="$1"
  here="$(chosen)"
  # A single pass over the list, tracking where we are and wrapping at both ends.
  target="$(
    entries | awk -v here="$here" -v dir="$direction" '
      { list[NR] = $0; if ($0 == here) at = NR }
      END {
        if (NR == 0) exit
        if (at == 0) at = 1
        if (dir == "next") at = (at % NR) + 1
        else at = ((at - 2 + NR) % NR) + 1
        print list[at]
      }'
  )"
  [ -n "$target" ] || return 0
  use "$target"
}

# Remember a choice and put it up. "generated" is the one value that is not a
# path.
use() {
  [ $# -ge 1 ] || { echo "wallpaper: use needs a value" >&2; exit 1; }
  if [ "$1" = generated ]; then
    remember generated
  else
    [ -f "$1" ] || { printf 'wallpaper: no such file: %s\n' "$1" >&2; exit 1; }
    remember "$1"
  fi
  apply
}

add_file() {
  [ $# -ge 1 ] || { echo "wallpaper: set needs a file" >&2; exit 1; }
  [ -f "$1" ] || { printf 'wallpaper: no such file: %s\n' "$1" >&2; exit 1; }
  dir="$(theme_dir)"
  mkdir -p "$dir"
  dst="$dir/$(basename "$1")"
  [ "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" = "$dst" ] || cp -f "$1" "$dst"
  use "$dst"
}

add_dir() {
  [ $# -ge 1 ] || { echo "wallpaper: add needs a folder" >&2; exit 1; }
  [ -d "$1" ] || { printf 'wallpaper: no such folder: %s\n' "$1" >&2; exit 1; }
  dir="$(theme_dir)"
  mkdir -p "$dir"
  n=0
  for f in "$1"/*; do
    [ -f "$f" ] || continue
    cp -f "$f" "$dir/" && n=$((n + 1))
  done
  printf 'Added %s background(s) to %s\n' "$n" "$(current_theme)"
}

case "${1:-}" in
  "" | pick) pick_one ;;
  apply) apply ;;
  list | ls)
    entries | while IFS= read -r e; do
      if [ "$e" = generated ]; then
        echo "generated"
      else
        basename "$e"
      fi
    done
    ;;
  set | add-file) shift; add_file "$@" ;;
  add) shift; add_dir "$@" ;;
  use) shift; use "$@" ;;
  next) step next ;;
  prev | previous) step prev ;;
  generated | theme | default) use generated ;;
  current) chosen ;;
  *) printf 'wallpaper: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
esac
