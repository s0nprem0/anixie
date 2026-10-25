#!/bin/sh
# The clipboard history.
#
#   clipboard            open the clipboard popup
#   clipboard --copy ID  put one entry back on the clipboard
#   clipboard --list     the raw `cliphist list` lines
#   clipboard --text ID  decode one entry as text
#   clipboard --images   decode thumbnails, printing "<id>\t<path>" per image
#   clipboard --image ID decode one image and print the path
#   clipboard --delete ID remove one entry
#   clipboard --wipe     remove the whole history
#
# cliphist owns the history; the shell owns the window. The popup reads the
# list, asks for a text or image decode when the selection changes, and copies
# through this script so the MIME type is decided in one place: piping a PNG
# through wl-copy without --type would put it on the clipboard as text and no
# image-aware application would accept it.
#
# Everything the popup needs is here rather than in QML, because QML would have
# to know where cliphist is and how to quote a preview that may hold tabs. The
# preview files live in a private runtime directory and are made only when asked
# for: an old history can hold hundreds of screenshots, and decoding all of them
# before the window appears would make the shortcut feel broken.

set -eu
umask 077

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

cliphist="@CLIPHIST@"
wl_copy="@WL_COPY@"
file="@FILE@"
quickshell="@QUICKSHELL@"

preview_dir() {
  runtime="${XDG_RUNTIME_DIR:-/tmp}"
  echo "$runtime/anixie-clipboard-$(id -u)"
}

decode_to() {
  id=$1
  path=$2
  if ! "$cliphist" decode "$id" >"$path"; then
    rm -f "$path"
    return 1
  fi
  [ -s "$path" ] || { rm -f "$path"; return 1; }
}

case "${1:-}" in
  --copy)
    [ $# -ge 2 ] || { echo "usage: clipboard --copy ID" >&2; exit 2; }
    id=$2

    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    if ! "$cliphist" decode "$id" >"$tmp"; then
      echo "clipboard: entry $id is no longer in the history" >&2
      exit 1
    fi
    if [ ! -s "$tmp" ]; then
      echo "clipboard: entry $id is empty" >&2
      exit 1
    fi

    mime=$("$file" -b --mime-type -- "$tmp")
    "$wl_copy" --type "$mime" <"$tmp"
    exit 0
    ;;
  --list)
    "$cliphist" list
    exit 0
    ;;
  --text)
    [ $# -ge 2 ] || { echo "usage: clipboard --text ID" >&2; exit 2; }
    "$cliphist" decode "$2"
    exit 0
    ;;
  --images)
    dir=$(preview_dir)/thumbs
    rm -rf "$dir"
    mkdir -p "$dir"
    chmod 700 "$dir"

    "$cliphist" list | awk \
      -v dir="$dir" \
      -v cliphist="$cliphist" \
      -v sq="'" '
      {
        tab = index($0, "\t")
        if (tab == 0) next

        id = substr($0, 1, tab - 1)
        preview = substr($0, tab + 1)
        if (preview !~ /^\[\[ binary data /) next
        if (images >= 40) exit

        path = dir "/" id
        cmd = sprintf("%s%s%s decode %s > %s%s%s", sq, cliphist, sq, id, sq, path, sq)
        if (system(cmd) == 0) {
          images++
          printf "%s\t%s\n", id, path
        }
      }
    '
    exit 0
    ;;
  --image)
    [ $# -ge 2 ] || { echo "usage: clipboard --image ID" >&2; exit 2; }
    dir=$(preview_dir)/previews
    mkdir -p "$dir"
    chmod 700 "$dir"

    path="$dir/preview-$2"
    decode_to "$2" "$path" || exit 1
    printf '%s\n' "$path"
    exit 0
    ;;
  --delete)
    [ $# -ge 2 ] || { echo "usage: clipboard --delete ID" >&2; exit 2; }
    id=$2

    line=$("$cliphist" list | awk -v id="$id" '
      {
        tab = index($0, "\t")
        if (tab > 0 && substr($0, 1, tab - 1) == id) {
          print
          exit
        }
      }
    ')
    [ -n "$line" ] || exit 0
    printf '%s\n' "$line" | "$cliphist" delete
    exit 0
    ;;
  --wipe)
    "$cliphist" wipe
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "clipboard: unknown argument \"$1\" (try --help)" >&2
    exit 2
    ;;
esac

if ! reply=$("$quickshell" ipc call clipboard open 2>/dev/null); then
  echo "clipboard: the shell is not running" >&2
  exit 1
fi

case "$reply" in
  ok | '"ok"' | ok.*) ;;
  *)
    echo "clipboard: the shell did not open the popup${reply:+ (said: $reply)}" >&2
    exit 1
    ;;
esac
