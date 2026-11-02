#!/bin/sh
# Feed new clipboard contents into cliphist.
#
# cliphist has no way to know where a selection came from, and password managers
# mark secrets with a hint in the offered MIME types. Storing those would put
# passwords in the history and, worse, in every preview the picker builds. Drop
# the selection instead of storing it.
#
#   clipboard-watch          watch text and images
#   clipboard-watch store    the child mode run once per new selection
#
# wl-paste runs the watched command directly, so the child mode is this script
# again with an explicit "store" argument.

set -u

cliphist="@CLIPHIST@"
wl_paste="@WL_PASTE@"

is_sensitive() {
  types=$("$wl_paste" --list-types 2>/dev/null || true)
  case "$types" in
    *passwordManagerHint*)
      return 0
      ;;
  esac
  return 1
}

case "${1:-watch}" in
  store)
    if is_sensitive; then
      # Drain the selection so wl-paste can finish its offer, but never let it
      # reach cliphist or, later, a preview file on disk.
      cat >/dev/null
      exit 0
    fi
    exec "$cliphist" store
    ;;
  watch)
    # wl-paste execs the watched command directly (it does not invoke a shell),
    # so pass the script and its "store" argument as separate argv entries.
    "$wl_paste" --type text --watch "$0" store &
    text_watcher=$!
    "$wl_paste" --type image --watch "$0" store &
    image_watcher=$!

    trap 'kill "$text_watcher" "$image_watcher" 2>/dev/null' TERM INT
    wait
    ;;
  *)
    echo "usage: clipboard-watch [watch|store]" >&2
    exit 2
    ;;
esac
