#!/bin/sh
# Desktop wallpaper.
#
# By default the wallpaper is not a picture but a gradient generated from the
# live palette, so every theme brings its own without shipping image files. Set
# anixie.theme.wallpaper.default to a picture to use one instead whenever a theme
# or output has no choice of its own. On top of that each theme has a folder of
# your own backgrounds, and the library scans the folders named in the theming
# options:
#
#   wallpaper                 pick one
#   wallpaper list            names from the library, one per line
#   wallpaper library [--json] the library, optionally as JSON
#   wallpaper set FILE        add a picture and use it
#   wallpaper add DIR         add every picture in a folder
#   wallpaper use FILE [--output NAME]
#                             use a picture, for one output or all of them
#   wallpaper record FILE [--output NAME]
#                             save a choice without applying it (theme.sh)
#   wallpaper next|prev [--random]
#   wallpaper rotate          rotate to a random wallpaper
#   wallpaper generated       go back to the palette gradient
#   wallpaper apply           re-apply the saved choice (run at login)
#   wallpaper current [--json]
#   wallpaper pause|resume|status
#
# Per-output selections are kept in wallpapers.json. Stills are drawn by the
# shell; videos are handed to mpvpaper. The resolved map is written to
# background.json, which the shell watches.
set -eu

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

STATE="@STATE_DIR@"
BACKGROUNDS="@DATA_DIR@/backgrounds"
WALLPAPER_DIRS=@WALLPAPER_DIRS@
WALLPAPER_RECURSIVE="@WALLPAPER_RECURSIVE@"
DEFAULT_WALLPAPER=@DEFAULT_WALLPAPER@
PALETTES="@PALETTES@"
DEFAULT_THEME="@DEFAULT_THEME@"
JQ="@JQ@"
MAGICK="@MAGICK@"
FFMPEG="@FFMPEG@"
MPVPAPER="@MPVPAPER@"
HYPRCTL="@HYPRCTL@"
PGREP="@PGREP@"
PKILL="@PKILL@"
QUICKSHELL="@QUICKSHELL@"
SHA256SUM="@SHA256SUM@"
STAT="@STAT@"
FLOCK="@FLOCK@"
WIDTH="@WIDTH@"
HEIGHT="@HEIGHT@"

GENERATED="$STATE/wallpaper.png"
WALLPAPERS="$STATE/wallpapers.json"
BACKGROUND_JSON="$STATE/background.json"
LIBRARY_CACHE="$STATE/library.json"
LIBRARY_STAMP="$STATE/library.stamp"
THUMBS="$STATE/thumbs"
POSTERS="$STATE/posters"
GENERATED_DIR="$STATE/wallpapers"

mkdir -p "$STATE" "$THUMBS" "$POSTERS" "$GENERATED_DIR"

# Selections are read-modify-write, and the rotation timer, the panel and the
# command line can all reach them. One lock around the writes is enough to keep
# a concurrent update from disappearing; reads are still atomic renames.
wallpaper_lock() {
  exec 9>"$STATE/.wallpapers.lock" || return 1
  "$FLOCK" -w 30 9 || return 1
}

wallpaper_unlock() {
  "$FLOCK" -u 9 2>/dev/null || true
  exec 9>&-
}

write_atomic() {
  file="$1"
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if cat >"$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

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

wallpapers_ensure() {
  [ -s "$WALLPAPERS" ] || printf '{"version":1,"themes":{}}\n' | write_atomic "$WALLPAPERS"
}

# shellcheck disable=SC2016
colour() {
  if [ -f "$STATE/live/palette.json" ]; then
    "$JQ" -r --arg k "$1" '.[$k]' "$STATE/live/palette.json"
  elif [ -f "$STATE/palette.json" ]; then
    "$JQ" -r --arg k "$1" '.[$k]' "$STATE/palette.json"
  else
    theme="$(current_theme)"
    [ "$theme" = "wallpaper" ] && theme="$DEFAULT_THEME"
    "$JQ" -r --arg n "$theme" --arg k "$1" '.[$n][$k]' "$PALETTES"
  fi
}

is_video() {
  case "$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')" in
    mp4 | mkv | webm | mov | m4v | avi | ogv) return 0 ;;
    *) return 1 ;;
  esac
}

is_image() {
  case "$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')" in
    jpg | jpeg | png | gif | webp | bmp | tif | tiff | avif) return 0 ;;
    *) return 1 ;;
  esac
}

is_media() {
  is_image "$1" || is_video "$1"
}

selection_json() {
  theme="$1"
  output="$2"
  wallpapers_ensure
  "$JQ" -c --arg t "$theme" --arg o "$output" '
    .themes[$t] as $theme
    | ($theme.outputs[$o] // $theme.fallback // null)
  ' "$WALLPAPERS"
}

selection() {
  theme="$1"
  output="$2"
  sel=$(selection_json "$theme" "$output")
  if [ "$sel" != "null" ]; then
    printf '%s' "$sel" | "$JQ" -r '[.mode, (.path // ""), (if .video then "1" else "0" end)] | @tsv'
    return
  fi

  old=$(chosen)
  if [ "$old" = generated ] || [ ! -f "$old" ]; then
    printf 'generated\t\t0\n'
  else
    if is_video "$old"; then video=1; else video=0; fi
    printf 'file\t%s\t%s\n' "$old" "$video"
  fi
}

chosen() {
  wallpapers_ensure
  theme=$(current_theme)
  value=$("$JQ" -r --arg t "$theme" '.themes[$t].fallback // empty | if .mode == "generated" then "generated" else (.path // empty) end' "$WALLPAPERS")
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return
  fi

  file="$STATE/wallpaper.$theme"
  if [ -f "$file" ]; then
    cat "$file"
  elif [ -n "$DEFAULT_WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
    printf '%s' "$DEFAULT_WALLPAPER"
  else
    echo generated
  fi
}

remember() {
  theme=$(current_theme)
  printf '%s\n' "$1" >"$STATE/wallpaper.$theme"
}

save_selection() {
  mode="$1"
  output="$2"
  path="$3"
  video="$4"
  theme=$(current_theme)

  wallpaper_lock || {
    printf 'wallpaper: could not lock the selection state\n' >&2
    return 1
  }
  wallpapers_ensure

  if [ -n "$output" ]; then
    "$JQ" --arg theme "$theme" --arg output "$output" --arg mode "$mode" --arg path "$path" --arg video "$video" '
      .themes[$theme].outputs[$output] = { mode: $mode, path: $path, video: ($video == "1") }
    ' "$WALLPAPERS" | write_atomic "$WALLPAPERS" || {
      wallpaper_unlock
      return 1
    }
  else
    "$JQ" --arg theme "$theme" --arg mode "$mode" --arg path "$path" --arg video "$video" '
      .themes[$theme].fallback = { mode: $mode, path: $path, video: ($video == "1") }
      | .themes[$theme].outputs = {}
    ' "$WALLPAPERS" | write_atomic "$WALLPAPERS" || {
      wallpaper_unlock
      return 1
    }
  fi

  if [ -z "$output" ]; then
    if [ "$mode" = generated ]; then
      remember generated
    else
      remember "$path"
    fi
  fi
  wallpaper_unlock
}

thumb_for() {
  path="$1"
  [ -f "$path" ] || return 0

  mtime=$("$STAT" -Lc %Y "$path" 2>/dev/null || printf '0')
  size=$("$STAT" -Lc %s "$path" 2>/dev/null || printf '0')
  key=$(printf '%s\n%s\n%s\n' "$path" "$mtime" "$size" | "$SHA256SUM")
  key=${key%% *}
  thumb="$THUMBS/$key.jpg"

  if [ ! -f "$thumb" ]; then
    source="$path"
    frame=""
    if is_video "$path"; then
      frame=$(mktemp "$THUMBS/frame.XXXXXX.jpg") || return 0
      "$FFMPEG" -y -loglevel error -i "$path" -frames:v 1 -q:v 2 "$frame" >/dev/null 2>&1 || {
        rm -f "$frame"
        return 0
      }
      source="$frame"
    fi
    if "$MAGICK" "$source" -thumbnail '320x180^' -gravity center -extent 320x180 \
      -quality 85 "$thumb.tmp" >/dev/null 2>&1; then
      mv "$thumb.tmp" "$thumb"
    else
      rm -f "$thumb.tmp"
      [ -n "$frame" ] && rm -f "$frame"
      return 0
    fi
    [ -n "$frame" ] && rm -f "$frame"
  fi

  printf '%s' "$thumb"
}

# A still from a video, for surfaces that cannot play it — the lock screen, and
# anything else that reads background.json. Keyed by path, mtime, size and the
# output's dimensions, so a changed video or a new resolution gets a new frame.
poster_for() {
  path="$1"
  output="$2"
  [ -f "$path" ] || return 0
  is_video "$path" || return 0

  mtime=$("$STAT" -Lc %Y "$path" 2>/dev/null || printf '0')
  size=$("$STAT" -Lc %s "$path" 2>/dev/null || printf '0')
  dims=$(output_size "$output")
  w=${dims%x*}
  h=${dims#*x}
  key=$(printf '%s\n%s\n%s\n%s\n' "$path" "$mtime" "$size" "$dims" | "$SHA256SUM")
  key=${key%% *}
  poster="$POSTERS/$key.jpg"

  if [ ! -f "$poster" ]; then
    tmp=$(mktemp "$POSTERS/.poster.XXXXXX.jpg") || return 0
    if "$FFMPEG" -y -loglevel error -i "$path" -frames:v 1 \
      -vf "scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h" \
      -q:v 2 "$tmp" >/dev/null 2>&1 && [ -s "$tmp" ]; then
      mv "$tmp" "$poster" || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  fi

  [ -f "$poster" ] && printf '%s' "$poster"
}

scan_dir() {
  dir="$1"
  [ -d "$dir" ] || return 0
  if [ "$WALLPAPER_RECURSIVE" = "true" ]; then
    find "$dir" -type f -print
  else
    find "$dir" -maxdepth 1 -type f -print
  fi | while IFS= read -r file; do
    is_media "$file" && printf '%s\n' "$file"
  done
}

library_paths() {
  {
    echo generated
    if [ -n "$DEFAULT_WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
      printf '%s\n' "$DEFAULT_WALLPAPER"
    fi
    scan_dir "$BACKGROUNDS/$(current_theme)"
    printf '%s\n' "$WALLPAPER_DIRS" | while IFS= read -r dir; do
      [ -n "$dir" ] && scan_dir "$dir"
    done
  } | awk '!seen[$0]++'
}

# The cache is only as good as the inputs it was built from. Every file's path,
# mtime and size goes into the fingerprint, so adding, removing or editing a
# picture (or changing the generated gradient) is noticed without throwing away
# the thumbnails that are still valid.
library_fingerprint() {
  {
    printf 'theme\t%s\n' "$(current_theme)"
    printf 'default\t%s\n' "$DEFAULT_WALLPAPER"
    if [ -n "$DEFAULT_WALLPAPER" ] && [ -f "$DEFAULT_WALLPAPER" ]; then
      "$STAT" -Lc 'file\t%n\t%Y\t%s' "$DEFAULT_WALLPAPER" 2>/dev/null || true
    fi
    if [ -f "$GENERATED" ]; then
      "$STAT" -Lc 'generated\t%n\t%Y\t%s' "$GENERATED" 2>/dev/null || true
    fi
    {
      printf '%s\n' "$BACKGROUNDS/$(current_theme)"
      printf '%s\n' "$WALLPAPER_DIRS"
    } | while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      if [ ! -d "$dir" ]; then
        printf 'missing\t%s\n' "$dir"
      elif [ "$WALLPAPER_RECURSIVE" = "true" ]; then
        find "$dir" -type f -printf 'file\t%p\t%T@\t%s\n' 2>/dev/null | sort
      else
        find "$dir" -maxdepth 1 -type f -printf 'file\t%p\t%T@\t%s\n' 2>/dev/null | sort
      fi
    done
  } | "$SHA256SUM" | cut -d ' ' -f 1
}

library_json() {
  refresh="${1:-}"
  stamp=$(library_fingerprint)
  if [ "$refresh" != "--refresh" ] && [ -s "$LIBRARY_CACHE" ] &&
    [ -f "$LIBRARY_STAMP" ] && [ "$(cat "$LIBRARY_STAMP" 2>/dev/null || true)" = "$stamp" ]; then
    cat "$LIBRARY_CACHE"
    return
  fi

  json=$(
    {
      printf 'Generated\tgenerated\t%s\t0\t1\n' "$(thumb_for "$GENERATED")"
      library_paths | while IFS= read -r path; do
        [ "$path" = generated ] && continue
        if is_video "$path"; then video=1; else video=0; fi
        printf '%s\t%s\t%s\t%s\t0\n' "$(basename "$path")" "$path" "$(thumb_for "$path")" "$video"
      done
    } | "$JQ" -R -s '
      split("\n")
      | map(select(length > 0) | split("\t") | {
          name: .[0],
          path: .[1],
          thumb: .[2],
          video: (.[3] == "1"),
          generated: (.[4] == "1")
        })
    '
  ) || return 1

  printf '%s\n' "$json" | write_atomic "$LIBRARY_CACHE" || true
  printf '%s\n' "$stamp" | write_atomic "$LIBRARY_STAMP" || true
  printf '%s\n' "$json"
}

generated_file() {
  output="$1"
  theme=$(current_theme)
  if [ -z "$output" ]; then
    printf '%s' "$GENERATED"
  else
    safe=$(printf '%s' "$output" | tr -c 'A-Za-z0-9._-' '_')
    printf '%s/%s-%s.png' "$GENERATED_DIR" "$theme" "$safe"
  fi
}

output_size() {
  output="$1"
  if [ -n "$output" ]; then
    size=$("$HYPRCTL" monitors -j 2>/dev/null | "$JQ" -r --arg output "$output" '
      .[] | select(.name == $output) | "\(.width)x\(.height)"
    ' | head -n 1)
    if [ -n "$size" ]; then
      printf '%s' "$size"
      return
    fi
  fi
  printf '%sx%s' "$WIDTH" "$HEIGHT"
}

generate() {
  output="$1"
  file=$(generated_file "$output")
  size=$(output_size "$output")
  mkdir -p "$(dirname "$file")"

  # The gradient is a pure function of the palette and the output size, and
  # rendering one costs more than the rest of `theme apply` together. Reuse the
  # file while both inputs are unchanged; `materialise` gives a new palette a
  # fresh mtime, so a theme change still invalidates it.
  if [ -s "$file" ] &&
    [ "$(cat "$file.size" 2>/dev/null || true)" = "$size" ] &&
    [ "$file" -nt "$STATE/live/palette.json" ]; then
    return 0
  fi

  bg=$(colour background)
  surface=$(colour surface)
  primary=$(colour primary)
  tmp=$(mktemp "$(dirname "$file")/.generate.XXXXXX.png") || return 1
  if ! "$MAGICK" -size "$size" \
    gradient:"$bg"-"$surface" \
    \( -size "$size" radial-gradient:none-"$primary" \
    -alpha set -channel A -evaluate multiply 0.10 +channel \) \
    -compose over -composite \
    -depth 8 \
    "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$size" >"$file.size" || true
}

output_names() {
  "$HYPRCTL" monitors -j 2>/dev/null | "$JQ" -r '.[].name' 2>/dev/null || true
}

apply() {
  wallpapers_ensure
  theme=$(current_theme)
  "$PKILL" -x mpvpaper >/dev/null 2>&1 || true
  rm -f "$STATE/video-paused"

  outputs=$(output_names)
  [ -n "$outputs" ] || outputs=""
  rows=$(mktemp "$STATE/.background.XXXXXX") || exit 1

  fallback_line=$(selection "$theme" "")
  fallback_mode=$(printf '%s' "$fallback_line" | cut -f1)
  fallback_path=$(printf '%s' "$fallback_line" | cut -f2)
  fallback_video=$(printf '%s' "$fallback_line" | cut -f3)
  if [ "$fallback_mode" = generated ] || [ ! -f "$fallback_path" ]; then
    generate "" || true
    if [ -f "$GENERATED" ]; then
      fallback_path="$GENERATED"
    else
      fallback_path=""
    fi
    fallback_video=0
  fi
  fallback_poster=""
  [ "$fallback_video" = 1 ] && fallback_poster=$(poster_for "$fallback_path" "")

  for output in $outputs; do
    line=$(selection "$theme" "$output")
    mode=$(printf '%s' "$line" | cut -f1)
    path=$(printf '%s' "$line" | cut -f2)
    video=$(printf '%s' "$line" | cut -f3)

    if [ "$mode" = generated ] || [ ! -f "$path" ]; then
      generate "$output" || true
      path=$(generated_file "$output")
      [ -f "$path" ] || path=""
      video=0
    fi

    poster=""
    if [ "$video" = 1 ]; then
      poster=$(poster_for "$path" "$output")
      if [ -n "$output" ] && [ -f "$path" ]; then
        "$MPVPAPER" -f -o "no-audio loop" "$output" "$path" >/dev/null 2>&1 || true
      fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$output" "$path" "$video" "$poster" >>"$rows"
  done

  if [ -z "$outputs" ]; then
    printf '\t%s\t%s\t%s\n' "$fallback_path" "$fallback_video" "$fallback_poster" >>"$rows"
  fi

  "$JQ" -R -s --arg path "$fallback_path" --arg video "$fallback_video" --arg poster "$fallback_poster" '
    {
      outputs: (split("\n") | map(select(length > 0) | split("\t")
        | { key: .[0], value: { path: .[1], video: (.[2] == "1"), poster: (.[3] // "") } }) | from_entries),
      fallback: { path: $path, video: ($video == "1"), poster: $poster }
    }
  ' "$rows" | write_atomic "$BACKGROUND_JSON"
  rm -f "$rows"

  if [ "$fallback_video" = 1 ]; then
    printf 'video\n%s\n' "$fallback_path" >"$STATE/background"
  else
    printf '%s\n' "$fallback_path" >"$STATE/background"
  fi
  "$QUICKSHELL" ipc call background reload >/dev/null 2>&1 || true
}

pick_one() {
  {
    printf 'Generated (from the %s palette)\tgenerated\t\t\t%s\n' "$(current_theme)" "$(thumb_for "$GENERATED")"
    library_paths | while IFS= read -r path; do
      [ "$path" = generated ] && continue
      printf '%s\t%s\t\t\t%s\n' "$(basename "$path")" "$path" "$(thumb_for "$path")"
    done
  } | pick --title "wallpaper — $(current_theme)" --on-select 'wallpaper use {}'
}

step() {
  direction="$1"
  random="${2:-}"
  here="$(chosen)"

  if [ "$random" = "--random" ] || [ "$random" = random ]; then
    target=$(
      library_paths | awk -v here="$here" '
        BEGIN { srand() }
        $0 == here { next }
        { list[NR] = $0 }
        END {
          if (NR == 0) exit
          print list[1 + int(rand() * NR)]
        }'
    )
  else
    target=$(
      library_paths | awk -v here="$here" -v dir="$direction" '
        { list[NR] = $0; if ($0 == here) at = NR }
        END {
          if (NR == 0) exit
          if (at == 0) at = 1
          if (dir == "next") at = (at % NR) + 1
          else at = ((at - 2 + NR) % NR) + 1
          print list[at]
        }'
    )
  fi

  [ -n "$target" ] || return 0
  use "$target"
}

use() {
  [ $# -ge 1 ] || { echo "wallpaper: use needs a value" >&2; exit 1; }
  target="$1"
  shift
  output=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        [ $# -ge 2 ] || { echo "wallpaper: --output needs a name" >&2; exit 1; }
        output="$2"
        shift 2
        ;;
      *) break ;;
    esac
  done

  wallpapers_ensure
  cp "$WALLPAPERS" "$STATE/.wallpapers.previous" 2>/dev/null || true
  theme_name=$(current_theme)
  legacy="$STATE/wallpaper.$theme_name"
  legacy_previous="$STATE/.wallpaper.previous"
  if [ -f "$legacy" ]; then
    cp "$legacy" "$legacy_previous" 2>/dev/null || true
  else
    rm -f "$legacy_previous"
  fi

  if [ "$target" = generated ]; then
    save_selection generated "$output" "" 0 || exit 1
  else
    [ -f "$target" ] || { printf 'wallpaper: no such file: %s\n' "$target" >&2; exit 1; }
    target=$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")
    if is_video "$target"; then video=1; else video=0; fi
    save_selection file "$output" "$target" "$video" || exit 1
  fi

  if [ "$target" != generated ] && [ "$(current_theme)" = wallpaper ]; then
    # The selection is already saved. Tell theme.sh so it does not record a
    # second, global choice on top of an output-specific one.
    if command -v theme >/dev/null 2>&1 && ANIXIE_WALLPAPER_RECORDED=1 theme wallpaper "$target"; then
      return
    fi
    printf 'wallpaper: could not derive a palette; keeping the previous theme\n' >&2
    if [ -f "$STATE/.wallpapers.previous" ]; then
      cp "$STATE/.wallpapers.previous" "$WALLPAPERS"
    fi
    if [ -f "$legacy_previous" ]; then
      cp "$legacy_previous" "$legacy"
    else
      rm -f "$legacy"
    fi
    apply
    return 1
  fi

  apply
}

# Save a selection without applying it. This is what `theme wallpaper FILE`
# uses, so the picture that produced a palette is the picture on screen without
# making theme.sh re-enter this command's picker/apply path.
record_selection() {
  [ $# -ge 1 ] || { echo "wallpaper: record needs a value" >&2; exit 1; }
  target="$1"
  shift
  output=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        [ $# -ge 2 ] || { echo "wallpaper: --output needs a name" >&2; exit 1; }
        output="$2"
        shift 2
        ;;
      *) break ;;
    esac
  done

  if [ "$target" = generated ]; then
    save_selection generated "$output" "" 0 || exit 1
  else
    [ -f "$target" ] || { printf 'wallpaper: no such file: %s\n' "$target" >&2; exit 1; }
    target=$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")
    if is_video "$target"; then video=1; else video=0; fi
    save_selection file "$output" "$target" "$video" || exit 1
  fi
}

add_file() {
  [ $# -ge 1 ] || { echo "wallpaper: set needs a file" >&2; exit 1; }
  [ -f "$1" ] || { printf 'wallpaper: no such file: %s\n' "$1" >&2; exit 1; }
  rm -f "$LIBRARY_CACHE" "$LIBRARY_STAMP"
  dir="$(theme_dir)"
  mkdir -p "$dir"
  dst="$dir/$(basename "$1")"
  [ "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" = "$dst" ] || cp -f "$1" "$dst"
  use "$dst"
}

add_dir() {
  [ $# -ge 1 ] || { echo "wallpaper: add needs a folder" >&2; exit 1; }
  [ -d "$1" ] || { printf 'wallpaper: no such folder: %s\n' "$1" >&2; exit 1; }
  rm -f "$LIBRARY_CACHE" "$LIBRARY_STAMP"
  dir="$(theme_dir)"
  mkdir -p "$dir"
  n=0
  for f in "$1"/*; do
    [ -f "$f" ] || continue
    is_media "$f" || continue
    cp -f "$f" "$dir/" && n=$((n + 1))
  done
  printf 'Added %s background(s) to %s\n' "$n" "$(current_theme)"
}

pause_video() {
  "$PKILL" -STOP -x mpvpaper 2>/dev/null || true
  printf '1\n' >"$STATE/video-paused"
}

resume_video() {
  "$PKILL" -CONT -x mpvpaper 2>/dev/null || true
  rm -f "$STATE/video-paused"
}

video_status() {
  if ! "$PGREP" -x mpvpaper >/dev/null 2>&1; then
    echo stopped
  elif [ -f "$STATE/video-paused" ]; then
    echo paused
  else
    echo running
  fi
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "" | pick) pick_one ;;
  apply) apply ;;
  list | ls)
    if [ "${2:-}" = "--json" ]; then
      library_json "${3:-}"
    else
      library_paths | while IFS= read -r entry; do
        [ "$entry" = generated ] && echo generated || basename "$entry"
      done
    fi
    ;;
  library)
    if [ "${2:-}" = "--json" ] || [ "${3:-}" = "--json" ]; then
      if [ "${3:-}" = "--refresh" ] || [ "${2:-}" = "--refresh" ]; then
        library_json --refresh
      else
        library_json
      fi
    else
      library_paths | while IFS= read -r entry; do
        [ "$entry" = generated ] && echo generated || basename "$entry"
      done
    fi
    ;;
  set | add-file) shift; add_file "$@" ;;
  add) shift; add_dir "$@" ;;
  use) shift; use "$@" ;;
  record) shift; record_selection "$@" ;;
  next) shift; step next "${1:-}" ;;
  prev | previous) shift; step prev "${1:-}" ;;
  rotate) step next --random ;;
  generated | theme | default) use generated ;;
  current)
    if [ "${2:-}" = "--json" ]; then
      if [ -f "$BACKGROUND_JSON" ]; then
        "$JQ" . "$BACKGROUND_JSON"
      else
        "$JQ" -n --arg path "$(chosen)" '{outputs:{},fallback:{path:$path,video:false,poster:""}}'
      fi
    else
      chosen
    fi
    ;;
  pause) pause_video ;;
  resume) resume_video ;;
  status) video_status ;;
  *) printf 'wallpaper: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
esac
