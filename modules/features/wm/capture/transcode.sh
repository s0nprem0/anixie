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
fuzzel="@FUZZEL@"
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

# Picked through fuzzel rather than a file dialog: it is already the launcher and
# the clipboard picker, and it filters as you type, which is the whole job here.
choose() {
  # $1 is the prompt, the rest are the choices.
  prompt="$1"
  shift
  printf '%s\n' "$@" | "$fuzzel" --dmenu --prompt="$prompt" --width 34
}

media_type() {
  mime=$(file -b --mime-type "$1" 2>/dev/null)
  case "$mime" in
    image/*) printf 'picture' ;;
    video/*) printf 'video' ;;
    *) return 1 ;;
  esac
}

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

  printf '%s\n' "$candidates" | "$fuzzel" --dmenu --prompt='transcode  ' --width 60
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

[ -n "$input" ] || input=$(choose_file) || exit 1
[ -n "$input" ] || exit 1
[ -f "$input" ] || die "no such file: $input"

type=$(media_type "$input") || die "not a picture or a video: $(file -b --mime-type "$input")"

if [ "$type" = "picture" ]; then
  [ -n "$format" ] || format=$(choose 'format  ' jpg png) || exit 1
  [ -n "$resolution" ] || resolution=$(choose 'size  ' high medium low) || exit 1
else
  [ -n "$format" ] || format=$(choose 'format  ' mp4 gif) || exit 1
  [ -n "$resolution" ] || resolution=$(choose 'size  ' 4k 1080p 720p) || exit 1
fi

[ -n "$format" ] && [ -n "$resolution" ] || exit 1

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
