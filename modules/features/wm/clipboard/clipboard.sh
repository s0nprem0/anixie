#!/bin/sh
# The clipboard history.
#
#   clipboard          pick an entry and put it back on the clipboard
#   clipboard --copy ID  put one entry back by id
#
# cliphist owns the history; this is only the choosing. `cliphist list` prints
# "<id>\t<preview>" per line, so the preview is what you read and the id is what
# the picker hands back — a row's text and the thing it means are not the same
# here, which is what the picker's value field is for.
#
# Images are shown as thumbnails rather than as cliphist's "<binary data>" line.
# The preview files live in a private runtime directory; they are built when the
# picker opens and handed to QML as file URLs. Copying is by MIME type, because
# piping a PNG through wl-copy without --type would put it on the clipboard as
# text and no image-aware application would accept it.
#
# awk rather than a tab-splitting read loop: a preview can contain tabs, so the
# only safe split is on the *first* one. Entries without one are skipped rather
# than guessed at, since an entry that cannot be decoded is worse than one that
# is not offered.

set -eu
umask 077

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

cliphist="@CLIPHIST@"
wl_copy="@WL_COPY@"
file="@FILE@"

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

runtime="${XDG_RUNTIME_DIR:-/tmp}"
preview_dir="$runtime/anixie-clipboard-$(id -u)"
rm -rf "$preview_dir"
mkdir -p "$preview_dir"
chmod 700 "$preview_dir"

"$cliphist" list | head -n 80 | awk \
  -v dir="$preview_dir" \
  -v cliphist="$cliphist" \
  -v sq="'" '
  {
    tab = index($0, "\t")
    if (tab == 0) next

    id = substr($0, 1, tab - 1)
    preview = substr($0, tab + 1)
    gsub(/[[:cntrl:]]/, " ", preview)

    if (preview ~ /^\[\[ binary data /) {
      name = preview
      sub(/^\[\[ binary data /, "", name)
      sub(/ \]\]$/, "", name)
      label = "Image · " name

      # Thumbnails are decoded on demand. An old history can hold hundreds of
      # screenshots; decoding all of them before the picker appears would make
      # the shortcut feel broken.
      if (images < 40) {
        path = dir "/" id
        cmd = sprintf("%s%s%s decode %s > %s%s%s", sq, cliphist, sq, id, sq, path, sq)
        if (system(cmd) == 0) {
          images++
          printf "%s\t%s\t%s\t%s\t%s\n", label, id, "image-x-generic", "", path
          next
        }
      }

      printf "%s\t%s\t%s\t\t\n", label, id, "image-x-generic"
      next
    }

    printf "%s\t%s\t\t\t\n", preview, id
  }
' | pick --title 'clipboard' --on-select 'clipboard --copy {}'
