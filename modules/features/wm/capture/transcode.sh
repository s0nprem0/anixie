#!/bin/bash
# Convert a picture or a video down to something small enough to send.
#
#   transcode                          pick a file, then a format, then a size
#   transcode FILE                     skip the file picker
#   transcode FILE FORMAT RESOLUTION   skip every prompt
#   transcode --path DIR               look in DIR instead of the usual places
#
#   Pictures: jpg, png          high, medium, low    (3160, 2160, 1080 px wide)
#   Videos:   mp4, gif          4k, 1080p, 720p
#
# The result is written next to the original, named for the size it was made at —
# demo-1080p.mp4 — and its path is copied to the clipboard as a file URI, which is
# what a chat client or a browser expects when a file is dropped onto it.
#
# A raw phone photo or a 4K recording is the usual reason to be here: both are far
# larger than the thing they are being sent through wants.

set -uo pipefail

magick="@MAGICK@"
ffmpeg="@FFMPEG@"
wl_copy="@WL_COPY@"

# Where the picker looks when it is not told. Only these two, because a fuzzy
# search over a whole home directory returns the same few names over and over.
search_paths=("$HOME/Pictures" "$HOME/Videos")

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

die() {
  printf 'transcode: %s\n' "$1" >&2
  exit 1
}

# Picked through the shell's picker rather than a file dialog: it is already the
# launcher and the clipboard picker, and it filters as you type, which is the
# whole job here.
choose_file() {
  candidates=$(
    for dir in "${search_paths[@]}"; do
      [ -d "$dir" ] || continue
      find "$dir" -maxdepth 3 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
        -o -iname '*.heic' -o -iname '*.tiff' -o -iname '*.bmp' \
        -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' \
        -o -iname '*.avi' \) 2>/dev/null
    done | sort
  )
  [ -n "$candidates" ] || die "no pictures or videos found in ${search_paths[*]}"

  printf '%s\n' "$candidates" | pick --title 'transcode' --on-select 'transcode {}'
}

# Single-quotes a value for the command the picker will run. The picker quotes
# the value it substitutes into `{}` and nothing else, so the arguments this
# script carries forward — a path with spaces in it, most of all — have to be
# quoted here.
quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

media_type() {
  mime=$(file -b --mime-type "$1" 2>/dev/null)
  case "$mime" in
    image/*) printf 'picture' ;;
    video/*) printf 'video' ;;
    *) return 1 ;;
  esac
}

output_path() {
  # The original's directory and stem, the size it was made at, the new format.
  dir=$(dirname -- "$1")
  base=$(basename -- "$1")
  stem=${base%.*}
  printf '%s/%s-%s.%s' "$dir" "$stem" "$3" "$2"
}

transcode_picture() {
  input="$1" format="$2" resolution="$3" output="$4"

  case "$resolution" in
    high) resize='3160x>' ;;
    medium) resize='2160x>' ;;
    low) resize='1080x>' ;;
    *) die "unknown picture size: $resolution (high, medium or low)" ;;
  esac

  case "$format" in
    jpg) "$magick" "$input" -resize "$resize" -quality 85 -strip "$output" ;;
    png)
      "$magick" "$input" -resize "$resize" -strip \
        -define png:compression-filter=5 \
        -define png:compression-level=9 \
        -define png:compression-strategy=1 \
        -define png:exclude-chunk=all \
        "$output"
      ;;
    *) die "unknown picture format: $format (jpg or png)" ;;
  esac
}

transcode_video() {
  input="$1" format="$2" resolution="$3" output="$4"

  case "$resolution" in
    4k) scale='scale=-2:2160' ;;
    1080p) scale='scale=-2:1080' ;;
    720p) scale='scale=-2:720' ;;
    *) die "unknown video size: $resolution (4k, 1080p or 720p)" ;;
  esac

  case "$format" in
    mp4)
      # x265 for 4k, where the file is large enough for the slower preset and the
      # extra ratio to be worth it; x264 elsewhere, where it is not.
      if [ "$resolution" = "4k" ]; then
        "$ffmpeg" -y -i "$input" -vf "$scale" -c:v libx265 -preset slow -crf 24 \
          -c:a aac -b:a 192k -movflags +faststart "$output"
      else
        "$ffmpeg" -y -i "$input" -vf "$scale" -c:v libx264 -preset fast -crf 23 \
          -c:a aac -b:a 192k -movflags +faststart "$output"
      fi
      ;;
    gif)
      # A generated palette, rather than ffmpeg's default 216 colours: screen
      # content is mostly flat colour, and the default bands it badly.
      "$ffmpeg" -y -i "$input" \
        -vf "fps=10,$scale:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        "$output"
      ;;
    *) die "unknown video format: $format (mp4 or gif)" ;;
  esac
}

# ---- arguments ---------------------------------------------------------------

input=""
format=""
resolution=""
positional=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --path)
      [ $# -ge 2 ] || die "--path needs a directory"
      search_paths=("$2")
      shift 2
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

# Indexed rather than shifted through, so an empty list needs no special case.
input="${positional[0]:-}"
format="${positional[1]:-}"
resolution="${positional[2]:-}"

# ---- prompts -----------------------------------------------------------------
#
# Each step hands the next one its answer as an argument, because the picker's
# answer goes to a process that has already exited: `transcode` with no arguments
# picks a file and runs `transcode <file>`, that one picks a format and runs
# `transcode <file> <format>`, and so on until all three are here and there is
# nothing left to ask. The old version asked the same questions from one process
# that sat and waited on three fuzzels in a row.
#
# The format list depends on what the file is, which is why the file has to be
# settled before this can offer anything.

if [ -z "$input" ]; then
  choose_file
  exit 0
fi

[ -f "$input" ] || die "no such file: $input"

type=$(media_type "$input") || die "not a picture or a video: $(file -b --mime-type "$input")"

if [ "$type" = "picture" ]; then
  formats="jpg
png"
  sizes="high
medium
low"
else
  formats="mp4
gif"
  sizes="4k
1080p
720p"
fi

if [ -z "$format" ]; then
  printf '%s\n' "$formats" | pick --title 'format' --on-select "transcode $(quote "$input") {}"
  exit 0
fi

if [ -z "$resolution" ]; then
  printf '%s\n' "$sizes" | pick --title 'size' --on-select "transcode $(quote "$input") $(quote "$format") {}"
  exit 0
fi

output=$(output_path "$input" "$format" "$resolution")

# ---- convert -----------------------------------------------------------------

if [ "$type" = "picture" ]; then
  transcode_picture "$input" "$format" "$resolution" "$output" || die "conversion failed"
else
  transcode_video "$input" "$format" "$resolution" "$output" || die "conversion failed"
fi

[ -s "$output" ] || die "conversion produced nothing"

# A file URI rather than the path: dropping a plain path onto a chat client or a
# browser usually does nothing, while a URI is what both accept as a file.
printf 'file://%s\n' "$(realpath -- "$output")" | "$wl_copy" --type text/uri-list

printf 'Saved %s\n' "$output"
